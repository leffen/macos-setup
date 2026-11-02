# steps/14-github-known-hosts.sh — pin github.com's SSH host keys
#
# ssh asks to confirm an unknown host key, interactively. When the parent is
# not interactive — brew, a script, a launchd job — that prompt cannot reach
# the terminal, ssh takes SIGTTIN and *stops*. The caller then waits on a child
# that will never finish, with no output and no error. That is what cost hours
# on 5 Sep 2026: `brew bundle` printed "Tapping azure/kubelogin" and sat there.
# Fixing the URL rewrite removed that particular path to it; this removes the
# prompt itself, and closes the trust-on-first-use gap while it is at it.
#
# Keys come from https://api.github.com/meta over TLS — GitHub publishing its
# own list — and NOT from ssh-keyscan, which would faithfully record whatever
# happens to answer on port 22.
#
# Position in the run does not currently matter: nothing before this clones
# from GitHub over SSH. If that changes, this has to move earlier.

KNOWN_HOSTS="$HOME/.ssh/known_hosts"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

log "Fetching GitHub's published SSH host keys..."
gh_meta="$(curl -fsSL --max-time 20 https://api.github.com/meta 2>/dev/null || true)"

published="$(printf '%s' "$gh_meta" | python3 -c '
import json, sys
try:
    keys = json.load(sys.stdin).get("ssh_keys") or []
except Exception:
    sys.exit(1)
for k in keys:
    print(k.strip())
' 2>/dev/null || true)"

if [[ -z "$published" ]]; then
  warn "could not fetch host keys from api.github.com — skipping"
  warn "known_hosts is unchanged; an SSH clone from GitHub may prompt"
else
  # ssh-keygen -F understands hashed known_hosts entries; plain grep does not.
  existing="$(ssh-keygen -F github.com 2>/dev/null | \grep -v '^#' || true)"

  if [[ -z "$existing" ]]; then
    while IFS= read -r key; do
      [[ -n "$key" ]] && printf 'github.com %s\n' "$key" >> "$KNOWN_HOSTS"
    done <<< "$published"
    chmod 600 "$KNOWN_HOSTS"
    ok "pinned $(printf '%s\n' "$published" | \grep -c .) github.com host keys"
  else
    # Never silently rewrite an existing entry — a changed host key is either a
    # GitHub rotation or someone in the middle, and only a human can tell which.
    mismatch=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      keypart="$(printf '%s' "$line" | awk '{print $(NF-1), $NF}')"
      printf '%s\n' "$published" | \grep -qF "$keypart" || mismatch=1
    done <<< "$existing"

    if [[ "$mismatch" -eq 0 ]]; then
      ok "github.com host keys already pinned and match GitHub's published list"
    else
      warn "a github.com key in known_hosts is NOT in GitHub's published list."
      warn "Not touching it. Verify by hand before trusting this host:"
      warn "  ssh-keygen -F github.com          # what we have"
      warn "  curl -s https://api.github.com/meta | python3 -m json.tool  # what GitHub says"
    fi
  fi
fi
