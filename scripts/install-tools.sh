#!/usr/bin/env bash
# Downloads pinned static binaries into /usr/local/bin.
# Kept out of the Dockerfile so a broken upstream URL is easy to spot and fix
# without rewriting layers.
set -euo pipefail

BIN=/usr/local/bin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# Strip a leading v from a tag: v1.2.3 -> 1.2.3
bare() { echo "${1#v}"; }

fetch() {
  # fetch <url> <output>
  echo ">> $1"
  curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"
}

echo "=== oc + kubectl ${OC_VERSION} ==="
fetch "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz" oc.tgz
tar -xzf oc.tgz -C "$BIN" oc kubectl

echo "=== helm ${HELM_VERSION} ==="
fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" helm.tgz
tar -xzf helm.tgz --strip-components=1 -C "$BIN" linux-amd64/helm

echo "=== argocd ${ARGOCD_VERSION} ==="
fetch "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" "$BIN/argocd"

echo "=== k9s ${K9S_VERSION} ==="
fetch "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" k9s.tgz
tar -xzf k9s.tgz -C "$BIN" k9s

echo "=== stern ${STERN_VERSION} ==="
fetch "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_$(bare "$STERN_VERSION")_linux_amd64.tar.gz" stern.tgz
tar -xzf stern.tgz -C "$BIN" stern

echo "=== yq ${YQ_VERSION} ==="
fetch "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" "$BIN/yq"

echo "=== kustomize ${KUSTOMIZE_VERSION} ==="
fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" kustomize.tgz
tar -xzf kustomize.tgz -C "$BIN" kustomize

echo "=== fzf ${FZF_VERSION} ==="
fetch "https://github.com/junegunn/fzf/releases/download/${FZF_VERSION}/fzf-$(bare "$FZF_VERSION")-linux_amd64.tar.gz" fzf.tgz
tar -xzf fzf.tgz -C "$BIN" fzf

echo "=== ripgrep ${RIPGREP_VERSION} ==="
fetch "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz" rg.tgz
tar -xzf rg.tgz --strip-components=1 -C "$BIN" "ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg"

echo "=== fd ${FD_VERSION} ==="
fetch "https://github.com/sharkdp/fd/releases/download/${FD_VERSION}/fd-${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" fd.tgz
tar -xzf fd.tgz --strip-components=1 -C "$BIN" "fd-${FD_VERSION}-x86_64-unknown-linux-musl/fd"

echo "=== bat ${BAT_VERSION} ==="
fetch "https://github.com/sharkdp/bat/releases/download/${BAT_VERSION}/bat-${BAT_VERSION}-x86_64-unknown-linux-musl.tar.gz" bat.tgz
tar -xzf bat.tgz --strip-components=1 -C "$BIN" "bat-${BAT_VERSION}-x86_64-unknown-linux-musl/bat"

echo "=== rclone ${RCLONE_VERSION} ==="
fetch "https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" rclone.zip
unzip -qo rclone.zip
install -m 0755 "rclone-${RCLONE_VERSION}-linux-amd64/rclone" "$BIN/rclone"

# tmux is not in the UBI9 repos, so zellij fills the multiplexer slot. Ships
# as a single static musl binary, which is simpler than building tmux and its
# libevent/ncurses dependencies from source.
echo "=== zellij ${ZELLIJ_VERSION} ==="
fetch "https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VERSION}/zellij-x86_64-unknown-linux-musl.tar.gz" zellij.tgz
tar -xzf zellij.tgz -C "$BIN" zellij

# Prompt. starship is a single static binary and works under bash or zsh, so
# there is no oh-my-zsh framework to maintain. The kubernetes module is the
# reason it earns its place here - current context and namespace visible on
# every line, which matters when you are one typo from the wrong cluster.
echo "=== starship ${STARSHIP_VERSION} ==="
fetch "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" starship.tgz
tar -xzf starship.tgz -C "$BIN" starship

# Fish-style history suggestions and command highlighting, vendored rather
# than cloned at runtime so the pod needs no internet.
echo "=== zsh plugins ==="
mkdir -p /usr/share/zsh-plugins
fetch "https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/${ZSH_AUTOSUGGESTIONS_VERSION}.tar.gz" zsh-as.tgz
tar -xzf zsh-as.tgz -C /usr/share/zsh-plugins --strip-components=1 --one-top-level=zsh-autosuggestions
fetch "https://github.com/zsh-users/zsh-syntax-highlighting/archive/refs/tags/${ZSH_SYNTAX_HIGHLIGHTING_VERSION}.tar.gz" zsh-sh.tgz
tar -xzf zsh-sh.tgz -C /usr/share/zsh-plugins --strip-components=1 --one-top-level=zsh-syntax-highlighting

# ls replacement with nerd-font file-type icons, colour by extension and
# per-file git status. coreutils ls will never do icons; this is what people
# mean when they ask for them.
echo "=== eza ${EZA_VERSION} ==="
fetch "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_x86_64-unknown-linux-musl.tar.gz" eza.tgz
tar -xzf eza.tgz -C "$BIN" ./eza
chmod 0755 "$BIN/eza"

# Nerd font for the client machine, not for this pod - the browser renders the
# terminal, so glyphs have to exist on the user's own PC. Shipping it here means
# every colleague installs the same font without hunting for a download.
#
# The upstream zip is ~125MB because it carries every weight and variant. We
# keep the four faces a terminal actually uses and re-zip, which lands at a few
# MB. Exposed at /work/fonts by the entrypoint so it is one click in the
# code-server file tree.
echo "=== nerd font (JetBrainsMono ${NERD_FONTS_VERSION}) ==="
fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/JetBrainsMono.zip" nf.zip
mkdir -p /opt/devbox-fonts/stage
# Exact filenames, no wildcards. '*NerdFont-Regular' also matches the NL
# (no-ligature) family - two near-identical names in the font picker - and
# 'JetBrainsMonoNerdFont-*' pulls in all nine weights. Four faces is what a
# terminal uses.
unzip -q -j nf.zip \
  'JetBrainsMonoNerdFont-Regular.ttf' \
  'JetBrainsMonoNerdFont-Bold.ttf' \
  'JetBrainsMonoNerdFont-Italic.ttf' \
  'JetBrainsMonoNerdFont-BoldItalic.ttf' \
  -d /opt/devbox-fonts/stage
cat > /opt/devbox-fonts/stage/INSTALL.txt <<'FONTEOF'
JetBrainsMono Nerd Font
=======================

Windows:
  1. Extract this zip.
  2. Select all four .ttf files, right-click, "Install for all users"
     (or just "Install" if that option is not offered).
  3. In devbox, open Settings (Ctrl+,), search "terminal font family",
     and set it to:

       JetBrainsMono Nerd Font

  4. Reopen the terminal.

Then switch the prompt to the glyph version:

    cp ~/.config/starship.nerdfont.toml ~/.config/starship.toml

The default prompt uses plain text on purpose, so it renders correctly for
anyone who has not installed this font.
FONTEOF
(cd /opt/devbox-fonts/stage && zip -q -r /opt/devbox-fonts/JetBrainsMonoNerdFont.zip .)
rm -rf /opt/devbox-fonts/stage nf.zip
ls -la /opt/devbox-fonts/
chmod -R g=u /opt/devbox-fonts

echo "=== code-server ${CODE_SERVER_VERSION} ==="
CS=$(bare "$CODE_SERVER_VERSION")
fetch "https://github.com/coder/code-server/releases/download/v${CS}/code-server-${CS}-linux-amd64.tar.gz" cs.tgz
mkdir -p /usr/local/lib/code-server
tar -xzf cs.tgz --strip-components=1 -C /usr/local/lib/code-server
ln -sf /usr/local/lib/code-server/bin/code-server "$BIN/code-server"

# VS Code extensions, staged as .vsix in the image.
#
# Open VSX is unreachable from the cluster, so extensions cannot be installed
# at runtime. They are downloaded here, where there is internet, and left as
# .vsix files. The entrypoint installs any that are missing on start, using
# `code-server --install-extension`.
#
# Copying the unpacked directories into the skeleton was the previous approach
# and it did not work: the extensions.json manifest is what code-server reads,
# and no-clobber seeding skipped it, so the folders were present and invisible.
# Installing via the CLI updates the manifest properly and is idempotent.
#
# jenkins-jack was removed in v0.1.6 and must not be reinstated. Its published
# vsix bundles exactly one native module, keytar, and the only binary in it is
# a Windows PE file - the marketplace publishes no per-platform variants. It
# `require`s keytar at module load, so the require throws on Linux and the
# extension never activates. That is why its tree views reported no data
# provider and its commands errored with nothing in any log.
#
# jenkins-workbench replaces it: no dependencies at all, no native binaries,
# credentials via VS Code SecretStorage rather than a system keyring, and it
# handles Jenkins CSRF crumbs.
echo "=== vscode extensions (staged as vsix) ==="
mkdir -p /opt/devbox-extensions

for spec in \
  "redhat:vscode-yaml:1.25.2026080708" \
  "eamodio:gitlens:2026.8.111607" \
  "ms-kubernetes-tools:vscode-kubernetes-tools:1.4.1" \
  "PKief:material-icon-theme:5.37.0" \
  "timonwong:shellcheck:0.39.5" \
  "Kelvin:vscode-sshfs:1.27.0" \
  "airizom:jenkins-workbench:1.51.0"; do
  pub="${spec%%:*}"; rest="${spec#*:}"; name="${rest%%:*}"; ver="${rest##*:}"
  fetch "https://open-vsx.org/api/${pub}/${name}/${ver}/file/${pub}.${name}-${ver}.vsix" \
        "/opt/devbox-extensions/${pub}.${name}.vsix"
done

# Refuse to ship a vsix carrying a Windows binary. This is the check that would
# have caught jenkins-jack before it was ever baked in: a PE file starts with
# "MZ", and an extension whose native module is built for the wrong platform
# fails at require time with no usable diagnostics in the editor.
python3 - <<'PYEOF'
import glob, sys, zipfile
bad = []
for path in sorted(glob.glob("/opt/devbox-extensions/*.vsix")):
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        bad.append(f"{path}: not a valid vsix")
        continue
    for entry in z.namelist():
        if entry.endswith(".node") and z.read(entry)[:2] == b"MZ":
            bad.append(f"{path}: {entry} is a Windows binary")
print("checked", len(glob.glob("/opt/devbox-extensions/*.vsix")), "vsix files")
if bad:
    print("\n".join("FAIL " + b for b in bad), file=sys.stderr)
    sys.exit(1)
PYEOF

chmod -R g=u /opt/devbox-extensions
ls -la /opt/devbox-extensions/

chmod 0755 "$BIN"/*
echo
echo "=== installed ==="
for t in oc kubectl helm argocd k9s stern yq kustomize fzf rg fd bat eza rclone zellij starship code-server; do
  printf '%-14s %s\n' "$t" "$(command -v "$t" || echo MISSING)"
done
