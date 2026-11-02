# steps/03-oh-my-zsh.sh — install oh-my-zsh
#
# KEEP_ZSHRC=yes  -> do not let the installer touch ~/.zshrc (we symlink ours in step 06)
# CHSH=no         -> macOS already defaults to zsh; skip the chsh prompt
# RUNZSH=no       -> do not drop into a new shell mid-setup

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "oh-my-zsh already installed"
else
  log "Installing oh-my-zsh..."
  RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "oh-my-zsh installed"
fi

# The `kube-ps1` plugin referenced in .zshrc sources the kube-ps1 script
# installed via Homebrew (see Brewfile). No extra plugin clone needed.

# ── Custom plugins ────────────────────────────────────────────
# These two are not bundled with oh-my-zsh and have no Homebrew formula that
# wires them into the plugin dir, so they are cloned. Both are listed in the
# plugins=() line in dotfiles/zshrc; without the clone that line silently
# does nothing.
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
for repo in \
  "zsh-users/zsh-autosuggestions:zsh-autosuggestions" \
  "zsh-users/zsh-syntax-highlighting:zsh-syntax-highlighting"
do
  slug="${repo%%:*}"; name="${repo##*:}"
  if [[ -d "$ZSH_CUSTOM/plugins/$name" ]]; then
    ok "plugin $name already present"
  elif git clone --depth=1 "https://github.com/$slug.git" \
       "$ZSH_CUSTOM/plugins/$name" >/dev/null 2>&1; then
    ok "plugin $name cloned"
  else
    warn "could not clone $name — it will be inert in the plugins line"
  fi
done
