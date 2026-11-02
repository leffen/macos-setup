# steps/18-git-signing-keys.sh — one SSH key for GitHub and commit signing
#
# Creates ~/.ssh/id_ed25519 if there is none, writes your identity and that
# key into ~/.gitconfig.local (dotfiles/gitconfig includes it), lists the key
# in ~/.ssh/allowed_signers so signatures VERIFY as well as sign, then proves
# both by signing and verifying a test message.
#
# Where the identity comes from, in order: GIT_NAME / GIT_EMAIL in the
# environment, then whatever ~/.gitconfig.local already says, then a prompt
# (only when run from a terminal). With none of them the step warns and skips;
# run `make keys` later. SIGNING_KEY overrides the key path.
#
# Signing uses the same key as SSH authentication. Upload the .pub to GitHub
# twice (Settings → SSH and GPG keys): as an Authentication key, and again as
# a Signing key, or GitHub shows your signed commits as "Unverified".

_gsk_key="${SIGNING_KEY:-$HOME/.ssh/id_ed25519}"
_gsk_local="$HOME/.gitconfig.local"
_gsk_signers="$HOME/.ssh/allowed_signers"
_gsk_get() { git config -f "$_gsk_local" --get "$1" 2>/dev/null || true; }

_gsk_name="${GIT_NAME:-$(_gsk_get user.name)}"
_gsk_email="${GIT_EMAIL:-$(_gsk_get user.email)}"
if [[ -t 0 ]]; then
  [[ -n "$_gsk_name" ]]  || read -r -p "  Your name, for commits: " _gsk_name
  [[ -n "$_gsk_email" ]] || read -r -p "  Your email, for commits: " _gsk_email
fi

if [[ -z "$_gsk_name" || -z "$_gsk_email" ]]; then
  warn "no git identity: set GIT_NAME and GIT_EMAIL, or run 'make keys' in a terminal"
  warn "until then 'git commit' fails, because dotfiles/gitconfig turns signing on"
else
  # ── 1. The key ───────────────────────────────────────────────
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [[ -f "$_gsk_key" ]]; then
    ok "using existing key $_gsk_key"
    if [[ ! -f "$_gsk_key.pub" ]]; then
      ssh-keygen -y -f "$_gsk_key" > "$_gsk_key.pub" || err "could not derive $_gsk_key.pub"
    fi
  elif [[ -t 0 ]]; then
    log "Creating $_gsk_key (ed25519). Choose a passphrase; steps/20 keeps it in your login keychain."
    ssh-keygen -t ed25519 -f "$_gsk_key" -C "$_gsk_email" && ok "created $_gsk_key"
  else
    # No terminal to ask for a passphrase in (CI, an agent). Better a working
    # key now than none; the warning says how to add a passphrase later.
    ssh-keygen -t ed25519 -f "$_gsk_key" -C "$_gsk_email" -N "" -q && ok "created $_gsk_key"
    warn "it has no passphrase; add one with: ssh-keygen -p -f $_gsk_key"
  fi
  [[ -f "$_gsk_key" ]] && chmod 600 "$_gsk_key"

  if [[ -f "$_gsk_key.pub" ]]; then
    # ── 2. Identity, in the untracked local file ─────────────────
    git config -f "$_gsk_local" user.name "$_gsk_name"
    git config -f "$_gsk_local" user.email "$_gsk_email"
    git config -f "$_gsk_local" user.signingkey "$_gsk_key.pub"
    ok "identity and signing key written to $_gsk_local"

    # ── 3. allowed_signers, so signatures verify ─────────────────
    _gsk_pub="$(awk '{print $1" "$2}' "$_gsk_key.pub")"
    touch "$_gsk_signers"
    if grep -qF "$_gsk_pub" "$_gsk_signers"; then
      ok "key already in $_gsk_signers"
    else
      printf '%s namespaces="git" %s\n' "$_gsk_email" "$_gsk_pub" >> "$_gsk_signers"
      ok "added key to $_gsk_signers"
    fi

    # ── 4. Prove it: sign, then verify against allowed_signers ───
    _gsk_tmp="$(mktemp -d)"
    if printf 'test' | ssh-keygen -Y sign -f "$_gsk_key" -n git - > "$_gsk_tmp/sig" 2>/dev/null \
       && printf 'test' | ssh-keygen -Y verify -f "$_gsk_signers" -I "$_gsk_email" -n git -s "$_gsk_tmp/sig" >/dev/null 2>&1; then
      ok "signing and verification both work"
    else
      warn "test signature failed. A passphrase-protected key has to be in ssh-agent first:"
      warn "    ssh-add --apple-use-keychain $_gsk_key     (steps/20 does this)"
    fi
    rm -rf "$_gsk_tmp"
  fi
fi

unset _gsk_key _gsk_local _gsk_signers _gsk_name _gsk_email _gsk_pub _gsk_tmp
unset -f _gsk_get
