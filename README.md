# devbox

A per-user development workstation that runs inside your Kubernetes cluster,
reached entirely through a browser.

It exists for a specific problem: locked-down corporate machines. If your
endpoint management wipes installed software, blocks script execution, or
withholds a working CLI, the machine stops being a place you can work. devbox
moves the workstation into the cluster, where you already have permission to
run things, and leaves the laptop as a thin client.

You log in with your existing cluster identity. There is no second account, no
VPN client, and nothing to install locally.

---

## What it is

A container image, a Helm chart, and a set of small tools written for this
environment.

- **Image** — UBI 9 with code-server (VS Code in the browser), a pinned
  toolchain, and seven pre-installed extensions.
- **Chart** — one release per person. Every object is named for the user, so
  `devbox-alice` and `devbox-bob` coexist without collisions.
- **Access** — an oauth-proxy sidecar authenticates against the cluster's own
  OAuth server and authorises with a SubjectAccessReview, so only the owner
  reaches the pod, its keys, and its shell history.
- **Storage** — two RWX volumes. `/home/dev` persists dotfiles, SSH config,
  kubeconfig, shell history, pinned CAs and editor state. `/work` holds
  clones and scratch.

Runs under an arbitrary UID as OpenShift assigns; the entrypoint synthesises a
passwd entry so ssh, git and zsh behave.

---

## Feature catalogue

### Purpose-built commands

| Command | What it does |
|---|---|
| `argo` | ArgoCD sync and health without the UI. Lists every Application with sync state, health and revision; `argo <name>` shows the failure reason and which resources are stuck; `argo watch <name>` blocks after a push until it settles, exiting 0 on success and 2 on failure. Reads the Application CRs through `oc`, so it needs no ArgoCD login or token. |
| `nexus` | Search and browse a Nexus repository from the terminal. `nexus <term>` searches every repository via the search API; docker results give a ready-made pull reference. Browsing fetches one directory level per keystroke, so a registry with thousands of blobs stays usable. |
| `trustca` | Make an internal CA trusted by *everything* in the box. Composes the cluster-injected bundle with anything pinned, then points `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO` and `NODE_EXTRA_CA_CERTS` at the result. Accepts PEM, DER or PKCS#7. |
| `sshadd` | Add an SSH session by guided prompt — name, host, user, key picked from a list. Writes `~/.ssh/config` correctly, inserting before any `Host *` block. |
| `sshprofiles` | Turns `~/.ssh/config` into VS Code terminal profiles and SSH FS entries, resolving each host through `ssh -G` so labels show the real destination: `ssh: app-server-1 (deploy@10.20.30.40)`. |
| `fwd` | Reach a remote service in your browser. `ssh -L` brings the port into the pod and code-server's proxy publishes it on your existing URL, behind the same login. No tunnel software on your machine. |
| `dx` | Capture command output to a file instead of copying it out of a terminal. Everything lands in `/work/out` for download. |

### Editor

code-server with extensions staged as `.vsix` in the image and installed at
start, so it works in clusters with no route to an extension marketplace.

- Jenkins Workbench — trigger, abort, replay, console output, test reports
- Kubernetes — browse workloads, read logs, exec
- SSH FS — remote file trees you can edit in place
- GitLens, YAML with schema validation, ShellCheck, Material icons

The build **fails** if any staged extension contains a Windows binary. That is
not hypothetical: a popular Jenkins extension ships a Windows-only native
module and cannot activate on Linux at all, with no usable error in the editor.

### Toolchain

Version-pinned so a rebuild months later produces the same thing.

- **Cluster** — `oc`, `helm`, `argocd`, `kustomize`, `k9s`, `stern`
- **Fleet** — `ansible-core`, `ansible-runner` (structured per-host artefacts),
  ClusterShell `clush` (parallel ssh with output gathering — `clush -b`
  collapses identical results and shows only the hosts that differ)
- **Shell** — zsh with autosuggestions and syntax highlighting, starship
  prompt showing cluster and namespace, zellij, eza, bat, fzf, ripgrep, fd
- **Diagnostics** — openssl, ldapsearch, dig, nc, tcpdump, strace, lsof
- **Transfer** — rsync, rclone, git, ssh

### Cluster credentials that do not expire

Two kubeconfig contexts. `incluster` authenticates with the projected
ServiceAccount token via `tokenFile` — the kubelet rotates it and `oc` re-reads
it per call, so there is no periodic re-login. Your own context is added
alongside for anything the ServiceAccount is not permitted to do.

RBAC is deliberately split: cluster-wide **read** via `cluster-reader`, and
**write only in the pod's own namespace** via a RoleBinding to `edit`. That is
enough to exec, port-forward and restart itself, and stops at the namespace
boundary.

---

## Quick start

```
helm install devbox-alice ./chart \
  --namespace devbox-alice --create-namespace \
  --set app_name=devbox-alice \
  --set env=dev \
  --set dev_hostname=apps.dev.example.com
```

Three secrets are created out of band, not by the chart and not in git:

| Secret | Holds |
|---|---|
| `<app_name>-proxy-secrets` | `session_secret` for oauth-proxy |
| `<app_name>-ssh` | SSH private keys, copied to `~/.ssh` at 0600 on start |
| `<app_name>-env-secrets` | optional environment, e.g. registry credentials |

Then grant the ServiceAccount cluster-wide read:

```
oc adm policy add-cluster-role-to-user cluster-reader \
  -z devbox-alice -n devbox-alice
```

Set `DEVBOX_TRUST_HOSTS` in values to any hosts whose issuing CA is not in the
cluster bundle; they are pinned on first start.

---

## Requirements

- OpenShift 4.x, or Kubernetes with an equivalent OAuth proxy and Route
- An RWX StorageClass (CephFS or similar). Avoid RWO block storage: a volume
  that cannot detach cleanly will strand the pod on a failed node.
- A registry the cluster can pull from

---

## Design notes

A few decisions that are not obvious and were each paid for once:

- **Node.js ignores the system trust store.** It carries its own compiled-in CA
  list, so an editor extension can fail TLS while `curl` on the same host
  succeeds. `NODE_EXTRA_CA_CERTS` is the only lever, and it is read once at
  process start — a tab reload will not pick up a new CA, only a restart will.
- **Probes run from the node's network namespace.** An httpGet probe against
  `127.0.0.1` checks the *node's* loopback, not the container's. Use exec
  probes for anything bound to container loopback.
- **A leaf certificate cannot anchor its own chain.** If a server sends only
  its leaf and that leaf is not self-signed, pinning it achieves nothing —
  you need the issuing CA. `trustca` says so rather than pretending.
- **Seeding by file copy skips manifests.** Copying extension directories in
  does not work, because the editor reads `extensions.json` and no-clobber
  seeding leaves it stale. Install from `.vsix` at start instead.

---

## Status

Used daily against a production OpenShift cluster. Versioned by image tag;
the chart's `image.tag` is the only thing that needs changing to roll forward.
