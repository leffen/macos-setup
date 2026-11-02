# steps/17-dock.sh — put the terminals in the Dock, in one group
#
# The stock Dock ships 20 Apple apps and no terminal at all, which is a poor
# default for this machine. Four emulators are installed (see docs/terminals.md)
# and the point of having them is trying them, which does not happen if reaching
# for one means Spotlight every time.
#
# Uses dockutil rather than `defaults write com.apple.dock persistent-apps
# -array-add`. The raw form takes a nested plist dict as a string argument, is
# unreadable, silently no-ops on a malformed entry, and has no notion of "is it
# already there" -- so a re-run appends duplicates. dockutil handles all three.
#
# Anchored after Claude so the tools cluster rather than scattering among the
# Apple apps. If Claude is missing, dockutil appends to the end, which is a fine
# fallback rather than an error.

if ! command -v dockutil >/dev/null 2>&1; then
  warn "dockutil not found — skipping Dock (did the Brewfile step run?)"
else
  # Only ever consider PINNED items.
  #
  # `dockutil --find` searches every section, including recentApps -- the
  # transient right-hand group macOS repopulates on its own. Using it as the
  # guard made this step report "removed Terminal" on every single run and
  # restart the Dock each time, because macOS put Terminal straight back the
  # moment it was next launched. Nothing was wrong with the Dock; the check was
  # asking the wrong question.
  #
  # --list emits: label<tab>path<tab>section<tab>plist, so field 3 is the
  # section and persistentApps is the only one worth acting on.
  dock_has() {
    dockutil --list 2>/dev/null \
      | awk -F'\t' -v want="$1" '$1 == want && $3 == "persistentApps" { found = 1 }
                                 END { exit !found }'
  }

  dock_changed=0
  dock_prev="Claude"

  for app in Ghostty iTerm kitty WezTerm; do
    app_path="/Applications/${app}.app"

    if [[ ! -d "$app_path" ]]; then
      warn "$app not installed — skipping"
      continue
    fi

    # Without this check a re-run would add a second copy of every terminal.
    if dock_has "$app"; then
      ok "$app already in the Dock"
    elif dockutil --add "$app_path" --after "$dock_prev" --no-restart >/dev/null 2>&1; then
      ok "added $app to the Dock"
      dock_changed=1
    else
      warn "could not add $app to the Dock"
    fi

    dock_prev="$app"
  done

  # ── Prune the stock apps ────────────────────────────────────
  #
  # A fresh macOS Dock is twenty Apple apps, most of which this machine will
  # never launch from a Dock icon. The list below is the media and PIM set --
  # everything removed here is still one Spotlight keystroke away, and none of
  # it is uninstalled.
  #
  # Terminal.app is in the list on purpose: with four better emulators sitting
  # two slots to the left, the stock one is only a way to end up in the wrong
  # terminal by accident.
  #
  # Kept deliberately: Safari and Chrome (two engines, both get used), Messages,
  # Mail, Calendar and Notes (reached often enough to earn a slot), System
  # Settings, Activity Monitor.
  for app in TV Music Games "iPhone Mirroring" Maps FaceTime "App Store" \
             Photos Phone Contacts Reminders Terminal; do
    if dock_has "$app"; then
      if dockutil --remove "$app" --no-restart >/dev/null 2>&1; then
        ok "removed $app from the Dock"
        dock_changed=1
      else
        warn "could not remove $app from the Dock"
      fi
    fi
    # Silent when absent: on a re-run every one of these is already gone, and
    # twelve "not present" lines would bury the lines that matter.
  done

  # ── Spacers between the groups ──────────────────────────────
  #
  # Six groups: launcher | browsers | chat & Claude | terminals | mail,
  # calendar, notes | settings. Four terminals in a row is hard to aim at
  # without a visual break either side of them.
  #
  # small-spacer rather than spacer: a full-width spacer is a whole tile, and
  # five of those would cost more Dock width than the apps they separate.
  #
  # Spacers carry no label, so dock_has cannot find them and the guard is a
  # count instead.
  #
  # WHY THIS DOES NOT CLEAR AND REBUILD
  #
  # The obvious shape is `dockutil --remove spacer-tiles` then add five fresh
  # ones, which would also repair the order. It cannot be used: in dockutil
  # 3.1.3 that command **crashes**, exit 133 (SIGTRAP), prints nothing at all,
  # and removes nothing. Written the obvious way with `|| true` after it, the
  # step would appear to work while quietly adding five MORE spacers on top of
  # the existing ones every run.
  #
  # So the count decides, and anything unexpected is left alone rather than
  # guessed at. 0 is the fresh-machine case and the only one worth automating.
  dock_spacers=$(dockutil --list 2>/dev/null \
    | awk -F'\t' '$1 == "" && $3 == "persistentApps"' | wc -l | tr -d ' ')

  if [[ "$dock_spacers" -eq 5 ]]; then
    ok "Dock spacers already in place"
  elif [[ "$dock_spacers" -eq 0 ]]; then
    for anchor in "Apps" "Google Chrome" "Claude" "WezTerm" "Notes"; do
      # Anchoring to an app that is not there would silently append the spacer
      # to the end of the Dock, which looks like a bug rather than a gap.
      dock_has "$anchor" || { warn "no $anchor in the Dock — spacer skipped"; continue; }
      if dockutil --add '' --type small-spacer --section apps --after "$anchor" \
           --no-restart >/dev/null 2>&1; then
        ok "spacer after $anchor"
        dock_changed=1
      else
        warn "could not add spacer after $anchor"
      fi
    done
  else
    warn "Dock has $dock_spacers spacers, expected 0 or 5 — leaving them alone"
    warn "drag the unwanted ones off the Dock and re-run; they cannot be"
    warn "removed programmatically (dockutil --remove spacer-tiles crashes)"
  fi

  # Restart once at the end, not per app: --no-restart above means the Dock
  # would otherwise keep the old layout until something else reloaded it.
  if [[ $dock_changed -eq 1 ]]; then
    killall Dock 2>/dev/null || true
    ok "Dock restarted"
  fi
fi
