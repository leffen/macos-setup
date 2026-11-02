# steps/22-azure-cli.sh — Azure CLI defaults and the `azl` login wrapper
#
# The binary comes from the Brewfile. ~/.azure/config is NOT tracked (az also
# keeps its own state there, e.g. first_run), so the settings that matter are
# re-applied here instead. Login itself stays manual.
#
# auto-upgrade OFF: with it on, az compares itself against Microsoft's release
# feed and runs `brew upgrade azure-cli` when it is behind. The formula lags
# that feed by days, so brew answers "already installed", the check still
# fails, and every az command — login included — loops on it. Seen 12 Oct 2026
# with 2.91.0 announced and the formula at 2.90.0. Brew owns upgrades here.
#
# login_experience_v2 OFF: skips the interactive subscription picker, which
# makes `az login` block on a prompt.

ensure_brew

if command -v az >/dev/null 2>&1; then
  if az config set auto-upgrade.enable=no core.login_experience_v2=off \
       --only-show-errors >/dev/null 2>&1; then
    ok "az: auto-upgrade off, subscription picker off"
  else
    warn "could not apply az config"
  fi
  link "$REPO_ROOT/scripts/tools/azl.sh" "$HOME/.local/bin/azl"
else
  warn "az not found — skipping (did the Brewfile step run?)"
fi
