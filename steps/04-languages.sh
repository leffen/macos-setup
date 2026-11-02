# steps/04-languages.sh — language runtimes & version managers

ensure_brew

# ── Go (official tarball into /usr/local/go) ──────────────────
if [[ -x /usr/local/go/bin/go ]]; then
  ok "Go already installed ($(/usr/local/go/bin/go version))"
else
  log "Installing Go..."
  GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
  GO_TARBALL="${GO_VERSION}.darwin-${GO_ARCH}.tar.gz"
  curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o "/tmp/${GO_TARBALL}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
  rm -f "/tmp/${GO_TARBALL}"
  ok "Installed ${GO_VERSION}"
fi

# ── nvm + Node LTS ────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  ok "nvm already installed"
else
  log "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1091
[[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
if command -v nvm >/dev/null 2>&1; then
  log "Installing Node LTS via nvm..."
  nvm install --lts
  nvm alias default 'lts/*' >/dev/null
  ok "Node $(node --version) installed"
fi

# ── Python via pyenv (pyenv itself comes from the Brewfile) ────
if command -v pyenv >/dev/null 2>&1; then
  PY_VERSION="$(pyenv install --list \
    | grep -E '^[[:space:]]*3\.[0-9]+\.[0-9]+$' \
    | tail -n1 | tr -d ' ')"
  if pyenv versions --bare | grep -qx "$PY_VERSION"; then
    ok "Python $PY_VERSION already installed"
  else
    log "Installing Python $PY_VERSION via pyenv..."
    pyenv install "$PY_VERSION"
  fi
  pyenv global "$PY_VERSION"
  ok "pyenv global set to $PY_VERSION"
else
  warn "pyenv not found — skipping Python (did the Brewfile step run?)"
fi

# ── Terraform via tfenv (tfenv itself comes from the Brewfile) ─
# The Brewfile deliberately has no terraform formula: tfenv owns
# $BREW_PREFIX/bin/terraform and a brew terraform cannot link past it. That
# leaves tfenv with no version selected on a fresh machine, where `terraform`
# fails with "Version could not be resolved" -- an error that names a missing
# file and not tfenv, so it reads like a broken install.
if command -v tfenv >/dev/null 2>&1; then
  if tfenv version-name >/dev/null 2>&1; then
    ok "Terraform $(tfenv version-name) already selected"
  else
    log "Installing latest Terraform via tfenv..."
    tfenv install latest
    tfenv use latest
    ok "tfenv default set to $(tfenv version-name)"
  fi
else
  warn "tfenv not found — skipping Terraform (did the Brewfile step run?)"
fi

# ── Rust (rustup) ─────────────────────────────────────────────
if [[ -x "$HOME/.cargo/bin/rustc" ]]; then
  ok "Rust already installed"
else
  log "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y
  ok "Rust installed"
fi

# ── bun ───────────────────────────────────────────────────────
if [[ -x "$HOME/.bun/bin/bun" ]]; then
  ok "bun already installed"
else
  log "Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  ok "bun installed"
fi

# ── pnpm ──────────────────────────────────────────────────────
# Newer pnpm (12.x here) installs to $PNPM_HOME/bin/pnpm, older ones to
# $PNPM_HOME/pnpm.
# Check both. Missing the new path made every re-run reinstall pnpm, and its
# installer appends to ~/.zshrc by writing a new file -- which broke the
# dotfile symlink each time (steps/06 then re-linked it, hiding the damage).
if [[ -x "$HOME/Library/pnpm/bin/pnpm" || -x "$HOME/Library/pnpm/pnpm" ]]; then
  ok "pnpm already installed"
else
  log "Installing pnpm..."
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  ok "pnpm installed"
fi
