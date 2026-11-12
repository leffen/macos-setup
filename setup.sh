#!/usr/bin/env bash
# setup.sh — bootstrap a fresh macOS to match this machine's setup.
#
# Usage:  ./setup.sh
#
# Safe to re-run: every step checks before it installs, and existing
# dotfiles are backed up before they are replaced.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

log "macOS setup starting (arch: $ARCH, Homebrew prefix: $BREW_PREFIX)"

# ── Preflight: refuse to start without a network ──────────────
# Nearly every step downloads something, and the failure mode when they cannot
# is spectacularly unhelpful. On 13 Sep a WARP reconnect took DNS down during
# `brew bundle`: the run emitted ~50 "has failed!" lines, carried on through
# four more steps, and signed off by asking whether the Brewfile step had run.
# It had -- it just could not resolve ghcr.io.
#
# This only catches a network that is already down when the run starts. It
# cannot catch one that dies mid-run, which is exactly what happened; that case
# belongs to steps/02, which re-probes when brew bundle fails.
if net_ok ghcr.io; then
  ok "network reachable"
else
  err "no usable network: cannot resolve or reach ghcr.io."
  err "    Every step below downloads something, so this run would fail dozens"
  err "    of times without telling you anything useful. Fix the network first."
  err "    On Cloudflare WARP, start with:  warp-cli status"
  exit 1
fi

# ── Preflight: sudo, once, up front ───────────────────────────
# steps/01 runs the Homebrew installer with NONINTERACTIVE=1, and in that mode
# it never prompts: it tries `sudo -n`, and with no cached credential it stops
# with "Insufficient permissions to install Homebrew to /opt/homebrew" -- which
# reads like a non-admin account even when the user IS an admin. That was the
# first thing a fresh Mac hit on 10 Nov 2026.
#
# So ask once here, at a terminal, and keep the timestamp fresh in the
# background: brew bundle alone outlasts sudo's 5-minute default, and several
# later steps (Go, apple/container, host name, power, ssh) need it too.
if [[ "$(id -u)" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
  if [[ -t 0 ]]; then
    log "Several steps need sudo -- asking once, now:"
    sudo -v || { err "sudo failed; cannot continue"; exit 1; }
  else
    err "no cached sudo credential and no terminal to ask at."
    err "    Run ./setup.sh from a terminal, or run 'sudo -v' first."
    exit 1
  fi
fi
if [[ "$(id -u)" -ne 0 ]]; then
  # Exits by itself when setup.sh does (kill -0 on our pid), and the trap
  # covers the normal path.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  _sudo_keepalive=$!
  trap 'kill "$_sudo_keepalive" 2>/dev/null || true' EXIT
fi

for step in "$SCRIPT_DIR"/steps/*.sh; do
  log "Running $(basename "$step")"
  # shellcheck disable=SC1090
  source "$step"
done

log "All steps complete."

cat <<'EOF'

────────────────────────────────────────────────────────────────
Manual follow-up — secrets are intentionally NOT handled by this
script. Restore these yourself:

  • SSH key: steps/18 created ~/.ssh/id_ed25519 if you had none. Add the
    .pub to GitHub TWICE (Settings → SSH and GPG keys): once as an
    Authentication key, once as a Signing key.
  • SOPS age key, only if you decrypt sops files:
        ~/.config/sops/age/keys.txt   (chmod 600)
  • Run:  gcloud auth login
  • Run:  gh auth login      # can also upload ~/.ssh/id_ed25519.pub
  • Run:  tea login add      # only if you use a Gitea instance
  • Restart the terminal (or run: exec zsh)
────────────────────────────────────────────────────────────────
EOF
