#!/bin/bash
# scripts/tools/fullscreen-awake.sh — hold off the idle lock while a full-screen
# app is frontmost.
#
# steps/12 locks the screen after 10 minutes idle (screen saver, then password
# immediately). The exception wanted: not while a browser or any other app is
# full screen and in front -- a video, a slide deck, a dashboard on the wall.
# macOS half-does this already: video players hold a "no display sleep"
# assertion, which also keeps the screen saver away. A full-screen app that is
# not playing video holds nothing, so it gets locked like any other.
#
# This fills that gap. Every few seconds it asks whether the frontmost app has
# a normal (layer 0) window covering a whole display. If so, it holds the same
# assertion a video player would (`caffeinate -d`); when that stops being true
# it lets go, and the idle timer applies again. Run at login by the LaunchAgent
# that steps/12 installs.
#
# Why window geometry and not the AXFullScreen attribute: reading AX attributes
# needs an Accessibility grant for whatever runs osascript, and those grants
# get revoked by macOS updates without a word. Window bounds from CoreGraphics
# need no grant at all. A maximised (zoomed) window does not count -- the menu
# bar and the Dock keep it short of the display -- which is the distinction
# wanted. Borderless "full screen" (games, some players) does count.
#
# Usage:
#   fullscreen-awake.sh           run the watch loop (what the LaunchAgent does)
#   fullscreen-awake.sh --check   print what it sees right now, once
#
# Transitions go to the unified log:
#   /usr/bin/log show --last 1h --predicate 'eventMessage CONTAINS "fullscreen-awake"'

set -uo pipefail

INTERVAL="${FULLSCREEN_AWAKE_INTERVAL:-15}"   # seconds between checks
TAG="fullscreen-awake"

# Prints "1 <app name>" when the frontmost app has a window covering a whole
# display, "0 <app name>" otherwise. Takes ~60 ms.
probe() {
  /usr/bin/osascript -l JavaScript <<'JXA' 2>/dev/null
ObjC.import('AppKit');
ObjC.import('CoreGraphics');
const app = $.NSWorkspace.sharedWorkspace.frontmostApplication;
const pid = app.processIdentifier;
const screens = [];
const ns = $.NSScreen.screens;
for (let i = 0; i < ns.count; i++) {
  const f = ns.objectAtIndex(i).frame;
  screens.push([f.size.width, f.size.height]);
}
// kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements
const wins = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1 | 16, 0))) || [];
const full = wins.some(w =>
  w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0 &&
  screens.some(([sw, sh]) => w.kCGWindowBounds.Width >= sw && w.kCGWindowBounds.Height >= sh));
`${full ? 1 : 0} ${app.localizedName.js}`;
JXA
}

if [[ "${1:-}" == "--check" ]]; then
  out="$(probe)" || { echo "probe failed"; exit 1; }
  if [[ "${out%% *}" == "1" ]]; then
    echo "full screen: yes (${out#* }) -- idle lock held off"
  else
    echo "full screen: no (${out#* }) -- idle lock applies"
  fi
  exit 0
fi

caff_pid=""
release() {
  if [[ -n "$caff_pid" ]]; then
    kill "$caff_pid" 2>/dev/null || true
    wait "$caff_pid" 2>/dev/null || true
    caff_pid=""
  fi
}
trap 'release; exit 0' INT TERM
trap release EXIT

logger -t "$TAG" "$TAG: started (every ${INTERVAL}s)"
while :; do
  out="$(probe)" || out="0 ?"
  if [[ "${out%% *}" == "1" ]]; then
    # caffeinate -w ties it to this process: if the loop dies, so does the hold.
    if [[ -z "$caff_pid" ]] || ! kill -0 "$caff_pid" 2>/dev/null; then
      /usr/bin/caffeinate -d -w $$ &
      caff_pid=$!
      logger -t "$TAG" "$TAG: full screen: ${out#* } -- holding off the idle lock"
    fi
  elif [[ -n "$caff_pid" ]]; then
    release
    logger -t "$TAG" "$TAG: left full screen (${out#* }) -- idle lock applies again"
  fi
  /bin/sleep "$INTERVAL"
done
