# devbox zsh. Copied into the home volume on first start only - edit freely,
# the entrypoint will not overwrite it.

export EDITOR=vim
export PATH="$HOME/bin:$PATH"

# History that actually remembers. Shared across every terminal, on the PVC,
# never truncated.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

setopt AUTO_CD INTERACTIVE_COMMENTS
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload -Uz compinit && compinit -d "$HOME/.zcompdump"

# Up/down search history by what you have already typed.
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

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

# Anything not Running or Succeeded, cluster-wide. First thing worth looking at
# during an incident.
alias badpods='oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded'

# VolumeAttachments stuck terminating - the failure that took another workload out for
# nine days in July 2026.
stuckvols() {
  oc get volumeattachment -o json | jq -r '.items[]
    | select(.metadata.deletionTimestamp != null)
    | "\(.metadata.name)  \(.spec.nodeName)  \(.metadata.deletionTimestamp)"'
}

[ -f /usr/share/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] \
  && source /usr/share/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
command -v fzf >/dev/null && source <(fzf --zsh 2>/dev/null)
command -v oc  >/dev/null && source <(oc completion zsh 2>/dev/null)

# One ssh-agent per pod, reused across shells, so a passphrase is typed once
# per pod lifetime. Exit code 2 from ssh-add means "cannot reach an agent",
# which is the signal to start a fresh one after a restart left a stale socket.
SSH_AGENT_ENV="$HOME/.ssh/agent.env"
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  [ -f "$SSH_AGENT_ENV" ] && source "$SSH_AGENT_ENV" >/dev/null 2>&1
  ssh-add -l >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    ssh-agent -s > "$SSH_AGENT_ENV" 2>/dev/null
    chmod 600 "$SSH_AGENT_ENV"
    source "$SSH_AGENT_ENV" >/dev/null 2>&1
  fi
fi

eval "$(starship init zsh)"

# Must be last - syntax highlighting wraps every widget defined before it.
[ -f /usr/share/zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] \
  && source /usr/share/zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Fleet work. clush runs a command or a piped script across a group and
# collapses identical output, so only the hosts that differ stand out:
#   clush -b -w @app_servers 'rpm -q java-21-openjdk'
#   clush -b -w @app_servers 'bash -s' < script.sh
# Wrap either in `dx run` to capture the result to /work/out for handing back.
alias fleet='clush -b -w'
