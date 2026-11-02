# steps/16-iterm2.sh — point iTerm2 at the prefs plist in this repo
#
# Every other terminal config is a symlink from steps/06-dotfiles.sh. iTerm2
# cannot be, because it does not read a config file: it reads its own defaults
# domain and rewrites the plist whenever a setting changes. Symlinking that
# into the repo would mean iTerm2 editing tracked files as a side effect of
# opening its preferences window.
#
# iTerm2's supported answer is a custom prefs folder. It copies prefs FROM the
# folder at launch, and offers to write changes back when it quits -- which is
# the behaviour you want here: tweak in the GUI, then `git diff` to see what
# changed and decide whether to keep it.
#
# The plist itself is generated rather than captured, so the palette matches
# Ghostty's bundled Vesper theme exactly rather than by transcription.

ITERM_PREFS_DIR="$DOTFILES_DIR/iterm2"

if [[ ! -d "/Applications/iTerm.app" ]]; then
  warn "iTerm2 not installed — skipping (did the Brewfile step run?)"
elif [[ ! -f "$ITERM_PREFS_DIR/com.googlecode.iterm2.plist" ]]; then
  err "no plist at $ITERM_PREFS_DIR — not pointing iTerm2 at an empty folder"
else
  # Setting this while iTerm2 runs is a coin flip: it may write its in-memory
  # prefs back over ours on quit, and the change looks like it silently did
  # nothing. Say so rather than racing it.
  if pgrep -qx iTerm2 2>/dev/null; then
    warn "iTerm2 is running — quit it and re-run this step, or its current"
    warn "prefs may overwrite the repo copy when it exits"
  fi

  current="$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)"
  if [[ "$current" == "$ITERM_PREFS_DIR" ]]; then
    ok "iTerm2 already reading prefs from $ITERM_PREFS_DIR"
  else
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ITERM_PREFS_DIR"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    ok "iTerm2 prefs -> $ITERM_PREFS_DIR (restart iTerm2 to pick it up)"
  fi
fi
