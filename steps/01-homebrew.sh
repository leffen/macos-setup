# steps/01-homebrew.sh — install Homebrew (arch-aware prefix)

if [[ -x "$BREW_BIN" ]]; then
  ok "Homebrew already installed at $BREW_PREFIX"
else
  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

ensure_brew
brew analytics off >/dev/null 2>&1 || true
ok "Homebrew ready ($(brew --version | head -n1))"
