# steps/15-claude-code.sh — Claude Code (native install)
#
# Public version of the private step: the same install, without the
# statusline registration, whose binary comes from a personal tap.
#
# Installed with Anthropic's native installer into ~/.local/bin, which
# dotfiles/zshenv puts first on PATH, and kept current by Claude Code itself.
# Not the Homebrew cask: Claude Code adds its own native copy regardless, so
# the cask only ever produced a second, older, shadowed `claude`. A leftover
# cask is reported here rather than removed; `brew uninstall --cask
# claude-code` clears it.
#
# Each self-update is a new binary, so on macOS 27 the App Data grant for
# Claude Code has to be given again after an update.

if [[ -x "$HOME/.local/bin/claude" ]]; then
  ok "Claude Code already installed (native, self-updating)"
else
  log "Installing Claude Code (native installer)..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "Claude Code installed to ~/.local/bin"
  else
    warn "Claude Code install failed — run by hand: curl -fsSL https://claude.ai/install.sh | bash"
  fi
fi
if brew list --cask claude-code >/dev/null 2>&1; then
  warn "Homebrew cask claude-code is also installed and shadowed — remove it: brew uninstall --cask claude-code"
fi
