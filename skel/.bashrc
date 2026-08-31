# devbox defaults. Copied into the home volume on first start only - edit
# freely, the entrypoint will not overwrite it.

[ -f /etc/bashrc ] && . /etc/bashrc

export EDITOR=vim
export PATH="$HOME/bin:$PATH"
export HISTFILE="$HOME/.bash_history"
export HISTSIZE=100000
export HISTFILESIZE=-1
export HISTTIMEFORMAT='%F %T  '
shopt -s histappend cmdhist
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

alias k=oc
# eza rather than ls: nerd-font file-type icons, colour by extension, and
# per-file git status in the long form. Falls back gracefully if the terminal
# font has no glyphs - you just get colour without icons.
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --group-directories-first --git'
  alias lt='eza --tree --level=2 --icons'
else
  alias ls='ls --color=auto'
  alias ll='ls -lah --color=auto'
fi
alias kctx='oc config get-contexts'
alias kns='oc project'
alias watchpods='watch -n5 oc get pods -o wide'

# Anything not Running or Succeeded, cluster-wide. The first thing worth
# looking at during an incident.
alias badpods='oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded'

# Volume attachments stuck terminating - the failure mode that took another workload
# out for nine days in July 2026.
stuckvols() {
  oc get volumeattachment -o json | jq -r '.items[]
    | select(.metadata.deletionTimestamp != null)
    | "\(.metadata.name)  \(.spec.nodeName)  \(.metadata.deletionTimestamp)"'
}

command -v fzf >/dev/null && eval "$(fzf --bash 2>/dev/null)"
command -v oc  >/dev/null && source <(oc completion bash 2>/dev/null)

eval "$(starship init bash)"


# One ssh-agent per pod, reused across shells and terminals, so a passphrase is
# typed once per pod lifetime instead of once per connection. The env file is
# on the home volume, so after a pod restart the socket path is stale - exit
# code 2 from ssh-add means "cannot reach an agent", which is the signal to
# start a fresh one. Exit 1 just means no keys loaded yet, which is fine.
SSH_AGENT_ENV="$HOME/.ssh/agent.env"
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  [ -f "$SSH_AGENT_ENV" ] && . "$SSH_AGENT_ENV" >/dev/null 2>&1
  ssh-add -l >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    ssh-agent -s > "$SSH_AGENT_ENV" 2>/dev/null
    chmod 600 "$SSH_AGENT_ENV"
    . "$SSH_AGENT_ENV" >/dev/null 2>&1
  fi
fi

# Fleet work. clush runs a command or a piped script across a group and
# collapses identical output, so only the hosts that differ stand out:
#   clush -b -w @app_servers 'rpm -q java-21-openjdk'
#   clush -b -w @app_servers 'bash -s' < script.sh
# Wrap either in `dx run` to capture the result to /work/out for handing back.
alias fleet='clush -b -w'
