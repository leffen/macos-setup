# steps/27-fonts.sh — keep one copy of Geist Mono, the variable font
#
# The font-geist-mono cask installs Geist Mono twice into ~/Library/Fonts:
# 18 static OTFs and the variable TTFs (GeistMono[wght].ttf plus the italic).
# Both sets carry the same PostScript names -- GeistMono-Regular, -Bold, ... --
# so Core Text picks one of the two per lookup, and a terminal asking for
# "GeistMono-Regular" can get a different file from the one beside it. On
# 9 Nov that was part of why iTerm2's text looked off next to Ghostty.
#
# The variable TTFs cover every weight and italic, so the OTFs are the ones to
# drop. A cask reinstall or upgrade puts them back; re-running this step takes
# them out again. They are only removed while the variable font is present, so
# this can never leave the machine with no Geist Mono at all.

FONTS_DIR="$HOME/Library/Fonts"

if [[ ! -f "$FONTS_DIR/GeistMono[wght].ttf" ]]; then
  warn "variable Geist Mono not in $FONTS_DIR — leaving the OTFs alone"
  warn "(did the Brewfile step install font-geist-mono?)"
else
  otfs="$(find "$FONTS_DIR" -maxdepth 1 -name 'GeistMono-*.otf' | wc -l | tr -d ' ')"
  if [[ "$otfs" == "0" ]]; then
    ok "Geist Mono: only the variable font is installed"
  else
    find "$FONTS_DIR" -maxdepth 1 -name 'GeistMono-*.otf' -delete
    ok "Geist Mono: removed $otfs static OTFs that duplicated the variable font"
    warn "restart open terminals so they stop using the removed font files"
  fi
  unset otfs
fi
unset FONTS_DIR
