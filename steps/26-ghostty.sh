# steps/26-ghostty.sh — Ghostty launches with one fresh window
#
# dotfiles/ghostty-config already says `window-save-state = never`, yet on
# 31 Oct Ghostty still came back with every old window. Its defaults domain had
# NSQuitAlwaysKeepsWindows = 1 -- the AppKit flag that restores windows on
# relaunch -- written at 17:29, the minute `brew bundle` upgraded the cask.
# Ghostty manages that key itself from window-save-state, so it can drift
# from the config file with nothing to show for it.
#
# ApplePersistenceIgnoreState is the AppKit-level override: with it set, the
# app never restores saved window state at launch, whatever that flag says.
# Ghostty does not touch it, so it stays put across upgrades. Both are
# written, and the saved state is cleared so the next launch starts clean.
#
# Ghostty writes its defaults back when it quits, so writing them while it
# runs can be undone on exit. Say so rather than racing it.

GHOSTTY_DOMAIN="com.mitchellh.ghostty"
GHOSTTY_SAVED_STATE="$HOME/Library/Saved Application State/$GHOSTTY_DOMAIN.savedState"

if [[ ! -d /Applications/Ghostty.app ]]; then
  warn "Ghostty not in /Applications — skipping (did the Brewfile step run?)"
else
  if pgrep -qx ghostty 2>/dev/null; then
    warn "Ghostty is running — quit it and re-run this step, or it may write"
    warn "its window-restore flag back when it exits"
  fi

  ignore="$(defaults read "$GHOSTTY_DOMAIN" ApplePersistenceIgnoreState 2>/dev/null || true)"
  keep="$(defaults read "$GHOSTTY_DOMAIN" NSQuitAlwaysKeepsWindows 2>/dev/null || true)"
  if [[ "$ignore" == "1" && "$keep" != "1" ]]; then
    ok "Ghostty already set to start with a single window"
  else
    defaults write "$GHOSTTY_DOMAIN" ApplePersistenceIgnoreState -bool true
    defaults write "$GHOSTTY_DOMAIN" NSQuitAlwaysKeepsWindows -bool false
    ok "Ghostty set to start with a single window (no window restore)"
  fi

  if [[ -d "$GHOSTTY_SAVED_STATE" ]]; then
    rm -rf "$GHOSTTY_SAVED_STATE"
    ok "cleared Ghostty's saved window state"
  fi
  unset ignore keep
fi
unset GHOSTTY_DOMAIN GHOSTTY_SAVED_STATE
