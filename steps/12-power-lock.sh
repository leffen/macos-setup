# steps/12-power-lock.sh — power, screen saver and lock behaviour
#
# The machine should stay awake on AC (long builds, container workloads) but
# still lock itself when left alone. Those two pull in opposite directions,
# so the ordering constraint below matters.

#
# The exception: while a full-screen app is frontmost, the idle lock is held
# off -- see the fullscreen-awake section at the end.

SCREENSAVER_IDLE=600      # 10 minutes, in seconds
DISPLAY_SLEEP_MIN=15      # minutes; MUST exceed the screen saver idle time,
                          # otherwise the display blanks before the saver runs
                          # and the lock never engages.

# ── Never sleep while on the power adapter ────────────────────
if sudo pmset -c sleep 0; then
  ok "system sleep on AC power: never"
else
  warn "could not set AC sleep"
fi
if sudo pmset -c displaysleep "$DISPLAY_SLEEP_MIN"; then
  ok "display sleep on AC power: ${DISPLAY_SLEEP_MIN} min (5 min after the screen saver)"
else
  warn "could not set AC display sleep"
fi
log "battery settings left untouched"

# ── Screen saver after 10 minutes idle ────────────────────────
if defaults -currentHost write com.apple.screensaver idleTime -int "$SCREENSAVER_IDLE"; then
  ok "screen saver starts after $((SCREENSAVER_IDLE / 60)) min idle"
else
  warn "could not set the screen saver idle time"
fi

# ── Lock as soon as the screen saver starts ───────────────────
# sysadminctl needs the login password and reads it from the tty. It is typed
# straight into sysadminctl — never stored, echoed or logged by this repo.
CURRENT_LOCK="$(sysadminctl -screenLock status 2>&1 | sed -n 's/.*screenLock delay is \(.*\)/\1/p' || true)"
log "current lock delay: ${CURRENT_LOCK:-unknown}"
if [[ -t 0 ]]; then
  log "macOS will now ask for YOUR LOGIN PASSWORD to set the lock to immediate."
  if sysadminctl -screenLock immediate -password - < /dev/tty; then
    NEW_LOCK="$(sysadminctl -screenLock status 2>&1 | sed -n 's/.*screenLock delay is \(.*\)/\1/p' || true)"
    ok "lock delay is now: ${NEW_LOCK:-immediate}"
  else
    warn "could not set the lock delay automatically."
    warn "Set it by hand: System Settings > Lock Screen >"
    warn "  'Require password after screen saver begins...' -> Immediately"
  fi
else
  warn "no tty — set the lock delay by hand: System Settings > Lock Screen >"
  warn "  'Require password after screen saver begins...' -> Immediately"
fi

log "screen saver timing applies at the next login (or run: killall loginwindow)"

# ── Except while a full-screen app is frontmost ───────────────
# A full-screen browser or app should not get locked mid-use: a video, a slide
# deck, a dashboard on the wall. Video players already hold off the screen
# saver themselves; scripts/tools/fullscreen-awake.sh does the same for any
# full-screen app, holding a `caffeinate -d` assertion only while one is in
# front. Run from the repo, so `git pull` updates it; KeepAlive restarts it.
FSA_LABEL="com.macos-setup.fullscreen-awake"
FSA_PLIST="$HOME/Library/LaunchAgents/$FSA_LABEL.plist"
FSA_BODY="$(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Managed by macos-setup (steps/12-power-lock.sh) -->
<plist version="1.0">
<dict>
  <key>Label</key>                  <string>$FSA_LABEL</string>
  <key>ProgramArguments</key>       <array><string>$REPO_ROOT/scripts/tools/fullscreen-awake.sh</string></array>
  <key>RunAtLoad</key>              <true/>
  <key>KeepAlive</key>              <true/>
  <key>LimitLoadToSessionType</key> <string>Aqua</string>
  <key>ProcessType</key>            <string>Background</string>
</dict>
</plist>
PLIST
)"

FSA_UID="$(id -u)"
if [[ "$(cat "$FSA_PLIST" 2>/dev/null)" == "$FSA_BODY" ]] \
    && launchctl print "gui/$FSA_UID/$FSA_LABEL" >/dev/null 2>&1; then
  ok "full-screen exception running ($FSA_LABEL)"
else
  mkdir -p "$(dirname "$FSA_PLIST")"
  printf '%s\n' "$FSA_BODY" > "$FSA_PLIST"
  launchctl bootout "gui/$FSA_UID/$FSA_LABEL" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$FSA_UID" "$FSA_PLIST" >/dev/null 2>&1; then
    ok "full-screen exception installed: no idle lock while a full-screen app is in front"
  else
    warn "could not load $FSA_LABEL — the idle lock will apply even in full screen"
  fi
fi
unset FSA_LABEL FSA_PLIST FSA_BODY FSA_UID
