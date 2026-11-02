# steps/00-xcode-clt.sh — Xcode Command Line Tools
#
# Runs first because everything after it needs a working git and compiler:
# the Homebrew installer, `brew bundle`, rustup and the Go tarball all assume
# the CLT are already there. macOS ships no compiler on a fresh install, so on
# a genuinely new machine this is the one step that cannot be skipped.
#
# The install itself is a GUI dialog Apple will not let us drive headlessly,
# so the best we can do is trigger it and wait for the result.

if xcode-select -p >/dev/null 2>&1; then
  ok "Command Line Tools present at $(xcode-select -p)"
else
  warn "Command Line Tools not installed — opening Apple's installer"
  xcode-select --install >/dev/null 2>&1 || true
  log "Click Install in the dialog and accept the licence. Waiting (up to 45 min)..."
  waited=0
  until xcode-select -p >/dev/null 2>&1; do
    if [[ "$waited" -ge 2700 ]]; then
      err "Timed out waiting for Command Line Tools."
      return 1 2>/dev/null || exit 1
    fi
    sleep 15
    waited=$((waited + 15))
    [[ $((waited % 120)) -eq 0 ]] && log "still waiting... (${waited}s)"
  done
  ok "Command Line Tools installed"
fi

# git is the specific tool the later steps break on, so check it by name
# rather than trusting that xcode-select -p means the install finished.
if git --version >/dev/null 2>&1; then
  ok "$(git --version)"
else
  err "git is still unusable — the Command Line Tools did not finish installing."
  return 1 2>/dev/null || exit 1
fi
