# ~/.config/zsh/aliases.zsh — managed by macos-setup
# Aliases and shell functions, sourced from ~/.zshrc.

# ── Listing & search ──────────────────────────────────────────
# eza/bat/rg/fd supersede ls/cat/grep/find. Each is guarded so this file
# still works on a machine where the Brewfile has not been applied yet —
# without the guard, a missing tool would leave the alias pointing at
# nothing and break `ls` in every new shell.
#
# These are aliases, so they apply to interactive use only; scripts and
# functions still get the real binaries. To reach one by hand anyway,
# backslash-escape it: \grep, \cat, \ls.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -l --git --group-directories-first'
  alias la='eza -la --git --group-directories-first'
  alias lt='eza --tree --level=2'
else
  alias ls='ls -G'
  alias ll='ls -lG'
fi

# bat pages by default, which breaks `cat file | ...` expectations; --paging=never
# keeps it a drop-in. It already drops styling automatically when not on a tty.
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'

# rg takes `rg pattern path` like grep, but its flags are NOT grep's — notably
# it recurses by default and ignores .gitignore. Some flags collide outright:
# `grep -E` is extended-regex, `rg -E` is --encoding, so `grep -E "a|b"` fails
# with "unknown encoding". Use \grep when you mean the real thing.
if command -v rg >/dev/null 2>&1; then
  alias grep='rg'
else
  alias grep='grep --color=auto'
fi

command -v fd >/dev/null 2>&1 && alias find='fd'

alias duh='du -csh'

# ── Shortcuts ─────────────────────────────────────────────────
alias p=python
alias m=make
alias c=codium
alias manpath=false
alias whatismyip='curl ipecho.net/plain'

# ── SSH without host-key checking / known_hosts ───────────────
alias tssh="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# ── Kubernetes ────────────────────────────────────────────────
alias kctx="kubectx"
alias cx="kubectx"
alias bb='k run bb --image=busybox:1.28 --restart=Never --rm -it -- /bin/sh'
alias ww='watch -n 0.5 "kubectl config current-context; echo ''; kubectl config view | grep namespace; echo ''; kubectl get namespace,node,ingress,pod,svc,job,cronjob,deployment,rs,pv,pvc,secret,ep -o wide"'

# kubectl exec helper
xx() {
  kubectl exec -it "${1}" -- "$@"
}

# ── Git diff helpers (delta is the pager; see dotfiles/gitconfig) ──
unalias gd 2>/dev/null
unalias gdc 2>/dev/null
gd()  { git diff "$@"; }
gdc() { gd --cached "$@"; }

# ── SOPS encryption helpers ───────────────────────────────────
encrypt() {
  filename=$(basename -- "$1")
  extension="${filename##*.}"
  filename="${filename%.*}"
  sops --encrypt --age "$(grep public "${SOPS_AGE_KEY_FILE}" | awk '{ print $NF }')" "$2" "$3" "$1" >"$filename.enc.$extension"
}

encrypt_inplace() {
  sops --encrypt --in-place --age "$(grep public "${SOPS_AGE_KEY_FILE}" | awk '{ print $NF }')" "$2" "$3" "$1"
}

# ── Git SSH commit signing ────────────────────────────────────
# Your identity and key live in ~/.gitconfig.local, written by
# steps/18-git-signing-keys.sh. These only switch signing on or off per repo.
git-sign-on() {
  local key
  key="$(git config --get user.signingkey)"
  if [[ -z "$key" ]]; then
    echo "❌ no user.signingkey configured — run: make keys"
    return 1
  fi
  git config --local gpg.format ssh
  git config --local commit.gpgsign true
  echo "✅ Commit signing enabled for this repository ($key)"
}

# Disable signing for current repo
git-sign-off() {
  git config --local commit.gpgsign false
  echo "❌ Commit signing disabled for this repository"
}

# Show current git signing configuration
git-sign-status() {
  echo "📋 Current repository git configuration:"
  echo "   Email: $(git config --local user.email || echo 'not set')"
  echo "   Name: $(git config --local user.name || echo 'not set')"
  echo "   Signing key: $(git config --local user.signingkey || echo 'not set')"
  echo "   Auto-sign: $(git config --local commit.gpgsign || echo 'not set')"
  echo "   Format: $(git config --local gpg.format || echo 'not set')"
}
