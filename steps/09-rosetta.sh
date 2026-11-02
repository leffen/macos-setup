# steps/09-rosetta.sh — Rosetta 2, for running amd64 images
#
# Needed by the Apple container step that follows: an arm64 Mac cannot run
# an x86_64 Linux image without it, and a good share of published images are
# still amd64-only. No-op on Intel.

rosetta_installed() {
  [[ -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]] || pgrep -q oahd 2>/dev/null
}

if [[ "$ARCH" != "arm64" ]]; then
  ok "Intel Mac — Rosetta not applicable"
elif rosetta_installed; then
  ok "Rosetta 2 already installed"
else
  log "Installing Rosetta 2 (needed to run amd64/x86_64 Linux images)..."
  if softwareupdate --install-rosetta --agree-to-license; then
    if rosetta_installed; then
      ok "Rosetta 2 installed"
    else
      warn "installer reported success but Rosetta was not detected"
    fi
  else
    warn "Rosetta install failed — amd64 images will not run until it is installed"
  fi
fi
