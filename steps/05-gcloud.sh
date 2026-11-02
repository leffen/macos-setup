# steps/05-gcloud.sh — Google Cloud SDK, installed under ~/tools

mkdir -p "$HOME/tools"

# ── Google Cloud SDK ──────────────────────────────────────────
if [[ -d "$HOME/tools/google-cloud-sdk" ]]; then
  ok "Google Cloud SDK already present"
else
  log "Installing Google Cloud SDK..."
  GCLOUD_TARBALL="google-cloud-cli-darwin-${GCLOUD_ARCH}.tar.gz"
  curl -fsSL \
    "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_TARBALL}" \
    -o "/tmp/${GCLOUD_TARBALL}"
  tar -C "$HOME/tools" -xzf "/tmp/${GCLOUD_TARBALL}"
  rm -f "/tmp/${GCLOUD_TARBALL}"
  # Shell rc edits are skipped — .zshrc already sources the SDK's inc files.
  "$HOME/tools/google-cloud-sdk/install.sh" --quiet \
    --command-completion false --path-update false
  ok "Google Cloud SDK installed (run 'gcloud auth login' later)"
fi

# z (rupa/z) used to be installed here and sourced from .zshrc. zoxide
# supersedes it — same idea, faster, and it comes from the Brewfile — so the
# clone is gone. Nothing else referenced ~/tools/z.
