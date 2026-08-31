#!/usr/bin/env bash
# Prepares the home volume and the passwd entry, then hands off to CMD.
#
# Runs under whatever UID OpenShift assigned. Nothing here may assume it can
# write outside the group-0 writable paths.
set -euo pipefail

HOME_DIR=${DEVBOX_HOME:-/home/dev}
WORK_DIR=${DEVBOX_WORK:-/work}
SKEL=/etc/devbox-skel

# OpenShift assigns an arbitrary UID with no /etc/passwd entry. ssh, git and
# zsh all misbehave without one, so synthesise it. /etc/passwd is group-0
# writable for exactly this reason.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
  if [ -w /etc/passwd ]; then
    echo "dev:x:$(id -u):0:devbox user:${HOME_DIR}:${SHELL:-/bin/bash}" >> /etc/passwd
  else
    echo "warn: no passwd entry for uid $(id -u) and /etc/passwd is not writable" >&2
  fi
fi

mkdir -p \
  "${HOME_DIR}/bin" \
  "${HOME_DIR}/.ssh" \
  "${HOME_DIR}/.kube" \
  "${HOME_DIR}/.config" \
  "${HOME_DIR}/.local/share" \
  "${WORK_DIR}/out"

chmod 0700 "${HOME_DIR}/.ssh" 2>/dev/null || true

# Seed dotfiles once. The home directory is a PVC, so this must never
# overwrite what the user has changed - only fill in what is absent.
if [ -d "$SKEL" ]; then
  # -r to descend into .config, -n so nothing the user has edited is ever
  # overwritten. A top-level existence check would silently skip
  # .config/zellij/config.kdl, because the mkdir above already created
  # .config - which is exactly the trap this replaced.
  cp -rn "$SKEL"/. "${HOME_DIR}/" 2>/dev/null || true
fi

# SSH keys arrive from a Secret mounted read-only, which ssh rejects on
# permissions. Copy them into the home volume at 0600 instead of trying to
# chmod the mount.
if [ -d /run/secrets/devbox-ssh ]; then
  for k in /run/secrets/devbox-ssh/*; do
    [ -f "$k" ] || continue
    install -m 0600 "$k" "${HOME_DIR}/.ssh/$(basename "$k")"
  done
fi

# The nerd font lives in the image, not the volume. Symlinked into /work so it
# shows up in the code-server file tree, where a right-click downloads it to
# the user's PC - which is the only machine where installing it does anything.
if [ -d /opt/devbox-fonts ] && [ ! -e "${WORK_DIR}/fonts" ]; then
  ln -sfn /opt/devbox-fonts "${WORK_DIR}/fonts" 2>/dev/null || true
fi

# Extensions: install any staged .vsix that is not already present.
#
# Copying the unpacked directories in was tried and failed - code-server reads
# extensions.json as its manifest, and seeding never overwrites an existing
# file, so the folders landed and the editor never saw them. The CLI writes
# that manifest itself, and skips anything already installed, so this is
# idempotent and costs a second or two on a warm volume.
if [ -d /opt/devbox-extensions ]; then
  installed=$(code-server --list-extensions 2>/dev/null | tr 'A-Z' 'a-z' || true)
  for vsix in /opt/devbox-extensions/*.vsix; do
    [ -f "$vsix" ] || continue
    id=$(basename "$vsix" .vsix | tr 'A-Z' 'a-z')
    case "$installed" in
      *"$id"*) continue ;;
    esac
    echo "installing extension: $(basename "$vsix" .vsix)"
    code-server --install-extension "$vsix" --force >/dev/null 2>&1 \
      || echo "  warn: failed to install $(basename "$vsix")" >&2
  done
fi

# Certificate trust.
#
# The cluster-injected bundle covers only what the cluster was told to trust,
# which does not include the internal CA behind Nexus, Jenkins and the old
# legacy-cluster hosts. trustca composes the injected bundle with anything pinned into
# ca.d and every runtime is pointed at the result - including Node, which
# otherwise ignores the system store completely and carries its own list.
#
# DEVBOX_TRUST_HOSTS is a space-separated list from the ConfigMap. Hosts
# already pinned are skipped, so this costs nothing on a warm volume and a
# host that is unreachable at start-up never blocks the box from coming up.
mkdir -p "${HOME_DIR}/.config/devbox/ca.d"
if [ -n "${DEVBOX_TRUST_HOSTS:-}" ]; then
  for host_spec in ${DEVBOX_TRUST_HOSTS}; do
    if [ ! -s "${HOME_DIR}/.config/devbox/ca.d/${host_spec%%:*}.pem" ]; then
      echo "trusting ${host_spec}"
      trustca "$host_spec" >/dev/null 2>&1 \
        || echo "  warn: could not fetch a chain for ${host_spec}" >&2
    fi
  done
fi
trustca --rebuild >/dev/null 2>&1 || true

CA_BUNDLE="${HOME_DIR}/.config/devbox/ca-bundle.pem"
if [ -s "$CA_BUNDLE" ]; then
  # Only exported once the file exists and is non-empty. Pointing these at a
  # missing or truncated bundle would break every TLS call in the box, which
  # is far worse than the trust gap it is meant to close.
  export SSL_CERT_FILE="$CA_BUNDLE"
  export REQUESTS_CA_BUNDLE="$CA_BUNDLE"
  export CURL_CA_BUNDLE="$CA_BUNDLE"
  export GIT_SSL_CAINFO="$CA_BUNDLE"
  export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
fi

# Cluster credentials.
#
# The projected ServiceAccount token is rotated by the kubelet, so oc must read
# the file each time rather than hold a copy - `tokenFile` does exactly that,
# which is what stops the twice-daily "you must be logged in" cycle. Reads only:
# the SA is bound to cluster-reader, so `oc login` as yourself is still the way
# to change anything.
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
if [ -r "${SA_DIR}/token" ] && command -v oc >/dev/null 2>&1; then
  export KUBECONFIG="${HOME_DIR}/.kube/config"
  sa_ns=$(cat "${SA_DIR}/namespace" 2>/dev/null || echo default)
  oc config set-cluster incluster \
      --server=https://kubernetes.default.svc \
      --certificate-authority="${SA_DIR}/ca.crt" >/dev/null 2>&1 || true
  oc config set users.incluster.tokenFile "${SA_DIR}/token" >/dev/null 2>&1 || true
  oc config set-context incluster \
      --cluster=incluster --user=incluster \
      --namespace="${sa_ns}" >/dev/null 2>&1 || true
  # Do not steal the current context. If a previous `oc login` is still there,
  # leave it selected and let `oc config use-context incluster` be a choice.
  if ! oc config current-context >/dev/null 2>&1; then
    oc config use-context incluster >/dev/null 2>&1 || true
  fi
fi

# Shell history lives on the volume and is never truncated.
touch "${HOME_DIR}/.bash_history" "${HOME_DIR}/.zsh_history" 2>/dev/null || true

echo "devbox ready  uid=$(id -u)  gid=$(id -g)  home=${HOME_DIR}"
exec "$@"
