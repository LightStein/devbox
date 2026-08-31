# devbox - in-cluster workstation for SRE / DevOps.
#
# Built with internet access on a public runner, pushed to Docker Hub, then
# mirrored into Nexus. your organisation's own build agents have no egress, so the tool
# downloads below cannot run there - that is why this image is built outside
# and promoted in, the same way the a large vendor deployment base images are handled.
#
# Runs under an arbitrary UID assigned by OpenShift. Everything the user needs
# to write is group-0 writable, and the entrypoint synthesises a passwd entry
# so ssh, zsh and git behave.

# Pinned by digest, not tag: this is the exact base the image was built and
# tested against, so a rebuild months from now produces the same thing.
# Resolved from ubi9/ubi:latest on 2026-08-05.
FROM registry.access.redhat.com/ubi9/ubi@sha256:e79f79172a6779775e1733cb4f49cd5ef03a0703c68ec46c717f93b9ac4a5e71

ARG OC_VERSION=4.18.49
ARG HELM_VERSION=v3.21.3
ARG ARGOCD_VERSION=v3.5.0
ARG K9S_VERSION=v0.51.0
ARG STERN_VERSION=v1.34.0
ARG YQ_VERSION=v4.53.3
ARG KUSTOMIZE_VERSION=v5.8.1
ARG FZF_VERSION=v0.74.2
ARG RIPGREP_VERSION=15.2.0
ARG FD_VERSION=v10.4.2
ARG BAT_VERSION=v0.26.1
ARG RCLONE_VERSION=v1.75.0
ARG ZELLIJ_VERSION=v0.44.3
ARG STARSHIP_VERSION=v1.26.0
ARG ZSH_AUTOSUGGESTIONS_VERSION=v0.7.1
ARG ZSH_SYNTAX_HIGHLIGHTING_VERSION=0.8.0
ARG EZA_VERSION=v0.23.5
ARG NERD_FONTS_VERSION=v3.5.0
ARG CODE_SERVER_VERSION=4.131.0

ENV OC_VERSION=${OC_VERSION} \
    HELM_VERSION=${HELM_VERSION} \
    ARGOCD_VERSION=${ARGOCD_VERSION} \
    K9S_VERSION=${K9S_VERSION} \
    STERN_VERSION=${STERN_VERSION} \
    YQ_VERSION=${YQ_VERSION} \
    KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION} \
    FZF_VERSION=${FZF_VERSION} \
    RIPGREP_VERSION=${RIPGREP_VERSION} \
    FD_VERSION=${FD_VERSION} \
    BAT_VERSION=${BAT_VERSION} \
    RCLONE_VERSION=${RCLONE_VERSION} \
    ZELLIJ_VERSION=${ZELLIJ_VERSION} \
    STARSHIP_VERSION=${STARSHIP_VERSION} \
    ZSH_AUTOSUGGESTIONS_VERSION=${ZSH_AUTOSUGGESTIONS_VERSION} \
    ZSH_SYNTAX_HIGHLIGHTING_VERSION=${ZSH_SYNTAX_HIGHLIGHTING_VERSION} \
    EZA_VERSION=${EZA_VERSION} \
    NERD_FONTS_VERSION=${NERD_FONTS_VERSION} \
    CODE_SERVER_VERSION=${CODE_SERVER_VERSION}

# Core packages. This layer must succeed - everything here is in ubi-9 baseos
# or appstream.
# coreutils and curl are deliberately absent: UBI9 ships coreutils-single and
# curl-minimal, which conflict with the full packages and already provide what
# we need. python3.11 is installed alongside the base 3.9 because current
# ansible-core requires 3.11 or newer.
RUN dnf -y update \
 && dnf -y install \
      bash findutils diffutils file which \
      git tar gzip xz zip unzip \
      wget less \
      openssh-clients rsync \
      python3.11 python3.11-pip \
      openssl ca-certificates \
      procps-ng iputils \
      glibc-langpack-en \
      make gcc \
 && dnf clean all \
 && rm -rf /var/cache/dnf

# Best-effort packages. Some of these are absent from the UBI repos depending
# on release. Installed one at a time so a missing package is reported rather
# than failing the build - check the output and replace any MISSING entry with
# a static binary in install-tools.sh.
RUN for p in jq zsh vim-enhanced nano socat \
             bind-utils nmap-ncat openldap-clients \
             tcpdump traceroute lsof strace bash-completion; do \
      dnf -y install "$p" >/dev/null 2>&1 \
        && echo "ok      $p" \
        || echo "MISSING $p"; \
    done; \
    dnf clean all; rm -rf /var/cache/dnf

# ansible-runner: wraps ansible and emits a structured artefact tree per run -
# artifacts/<uuid>/ with stdout, rc, status and a JSON event stream per host.
# That turns "paste the output back" into "download one directory", and the
# events are machine-readable, so partial failures across a fleet stay legible.
#
# ClusterShell: clush, parallel ssh over node ranges (app-server[1-4]) with
# output gathering - `clush -b` collapses identical results across hosts and
# shows only the ones that differ. That is the fastest answer to "which of
# these twenty boxes is not like the others".
RUN python3.11 -m pip install --no-cache-dir --upgrade pip \
 && python3.11 -m pip install --no-cache-dir \
      ansible-core ansible-lint requests pyyaml jinja2 \
      ansible-runner ClusterShell \
 && ln -sf /usr/bin/python3.11 /usr/local/bin/python \
 && for b in ansible-runner clush nodeset cluset; do \
      test -x "/usr/local/bin/$b" || ln -sf "/usr/local/bin/$b" "/usr/local/bin/$b" 2>/dev/null || true; \
    done

COPY scripts/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh && /tmp/install-tools.sh && rm -f /tmp/install-tools.sh

# Skeleton config copied into the home volume on first start, not baked into
# it - the home directory is a PVC and must not be clobbered on restart.
COPY skel/ /etc/devbox-skel/
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/dx /usr/local/bin/dx
COPY scripts/nexus /usr/local/bin/nexus
COPY scripts/sshprofiles /usr/local/bin/sshprofiles
COPY scripts/fwd /usr/local/bin/fwd
COPY scripts/sshadd /usr/local/bin/sshadd
COPY scripts/trustca /usr/local/bin/trustca
COPY scripts/argo /usr/local/bin/argo

ENV HOME=/home/dev \
    DEVBOX_HOME=/home/dev \
    DEVBOX_WORK=/work \
    SHELL=/bin/bash \
    LANG=C.UTF-8

RUN mkdir -p /home/dev /work /usr/local/lib/code-server-data \
 && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dx /usr/local/bin/nexus \
                 /usr/local/bin/sshprofiles /usr/local/bin/fwd /usr/local/bin/sshadd \
                 /usr/local/bin/trustca /usr/local/bin/argo \
 # OpenShift runs this as a random UID in group 0. Everything writable must be
 # group-0 writable, and /etc/passwd must be writable so the entrypoint can add
 # an entry for that UID - without one, ssh and zsh refuse to behave.
 && chgrp -R 0 /home/dev /work /usr/local/lib/code-server-data /etc/passwd \
 && chmod -R g=u /home/dev /work /usr/local/lib/code-server-data \
 && chmod g=u /etc/passwd

WORKDIR /home/dev
USER 1001
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
