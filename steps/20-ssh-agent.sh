# steps/20-ssh-agent.sh — keep your SSH keys in the agent across logins
#
# macOS starts an ssh-agent for you, but it is EMPTY at every login, and
# `UseKeychain yes` alone does not change that: it only reads a saved
# passphrase when ssh(1) asks for one. Commit signing never runs ssh(1) — git
# calls `ssh-keygen -Y sign`, which can only reach a protected key through the
# agent — so without this, signing breaks after every reboot.
#
# This step does three things:
#   1. Adds a managed block to ~/.ssh/config (AddKeysToAgent, UseKeychain).
#      Only the block between the markers is ever rewritten; the rest of the
#      file is yours.
#   2. Stores each protected key's passphrase in the login keychain, once
#      (`ssh-add --apple-use-keychain`, which asks for it in a terminal).
#   3. Writes ~/.ssh/agent-keys, the manifest dotfiles/zprofile reads at login
#      to put every key back. Columns are tab-separated:
#      <fingerprint> <nopass|keychain> <path>

_sa_dir="$HOME/.ssh"
_sa_cfg="$_sa_dir/config"
_sa_manifest="$_sa_dir/agent-keys"
_sa_begin="# >>> macos-setup (steps/20-ssh-agent.sh) >>>"
_sa_end="# <<< macos-setup <<<"

mkdir -p "$_sa_dir"
chmod 700 "$_sa_dir"

# ── 1. ~/.ssh/config block ──────────────────────────────────────
_sa_block="$(printf '%s\nHost *\n  AddKeysToAgent yes\n  UseKeychain yes\n%s' "$_sa_begin" "$_sa_end")"
touch "$_sa_cfg"
chmod 600 "$_sa_cfg"
if grep -qF "$_sa_begin" "$_sa_cfg"; then
  # Replace our block in place, leaving everything around it untouched.
  _sa_tmp="$(mktemp)"
  awk -v b="$_sa_begin" -v e="$_sa_end" -v blk="$_sa_block" '
    $0 == b { print blk; skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$_sa_cfg" > "$_sa_tmp" && cat "$_sa_tmp" > "$_sa_cfg"
  rm -f "$_sa_tmp"
  ok "$_sa_cfg block up to date"
else
  # Host * goes LAST: ssh_config takes the first value it sees for each
  # keyword, so your own Host entries above keep priority.
  printf '\n%s\n' "$_sa_block" >> "$_sa_cfg"
  ok "added AddKeysToAgent/UseKeychain block to $_sa_cfg"
fi

# ── 2 + 3. Keychain and manifest ────────────────────────────────
_sa_new="$(mktemp)"
printf '# Written by steps/20-ssh-agent.sh; read by ~/.zprofile at login.\n' > "$_sa_new"
printf '# Columns are tab-separated: fingerprint, nopass|keychain, path.\n' >> "$_sa_new"
_sa_count=0
for _sa_key in "$_sa_dir"/id_*; do
  [[ -f "$_sa_key" && "$_sa_key" != *.pub && -f "$_sa_key.pub" ]] || continue
  _sa_fp="$(ssh-keygen -lf "$_sa_key.pub" 2>/dev/null | awk '{print $2}')"
  [[ -n "$_sa_fp" ]] || continue
  if ssh-keygen -y -P "" -f "$_sa_key" >/dev/null 2>&1; then
    _sa_mode=nopass
  else
    _sa_mode=keychain
    if ssh-add -l 2>/dev/null | grep -qF "$_sa_fp"; then
      :   # already in the agent, so the passphrase is stored or was just typed
    elif [[ -t 0 ]]; then
      log "Storing the passphrase for $(basename "$_sa_key") in the login keychain..."
      ssh-add --apple-use-keychain "$_sa_key" || warn "could not add $_sa_key"
    else
      warn "$(basename "$_sa_key") is passphrase-protected; run 'make ssh-agent' in a terminal to store it"
    fi
  fi
  printf '%s\t%s\t%s\n' "$_sa_fp" "$_sa_mode" "$_sa_key" >> "$_sa_new"
  _sa_count=$((_sa_count + 1))
done
cat "$_sa_new" > "$_sa_manifest"
rm -f "$_sa_new"
chmod 600 "$_sa_manifest"
ok "$_sa_count key(s) recorded in $_sa_manifest"

unset _sa_dir _sa_cfg _sa_manifest _sa_begin _sa_end _sa_block _sa_tmp _sa_new \
      _sa_count _sa_key _sa_fp _sa_mode
