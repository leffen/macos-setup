# steps/06-dotfiles.sh — symlink dotfiles (anything already there is backed up)

log "Linking dotfiles..."

link "$DOTFILES_DIR/zshenv"          "$HOME/.zshenv"
link "$DOTFILES_DIR/zprofile"        "$HOME/.zprofile"
link "$DOTFILES_DIR/zshrc"           "$HOME/.zshrc"
link "$DOTFILES_DIR/gitconfig"       "$HOME/.gitconfig"
# gitconfig sets core.excludesfile = ~/.gitignore, so without this line that
# setting points at a file that does not exist -- which is exactly what was
# found on this machine on 16 Aug: global excludes configured, and silently
# doing nothing for months.
link "$DOTFILES_DIR/gitignore"       "$HOME/.gitignore"
link "$DOTFILES_DIR/aliases.zsh"     "$HOME/.config/zsh/aliases.zsh"
link "$DOTFILES_DIR/prompt.zsh"      "$HOME/.config/zsh/prompt.zsh"
link "$DOTFILES_DIR/ghostty-config"  "$HOME/.config/ghostty/config"
link "$DOTFILES_DIR/kitty.conf"      "$HOME/.config/kitty/kitty.conf"
link "$DOTFILES_DIR/wezterm.lua"     "$HOME/.config/wezterm/wezterm.lua"
link "$DOTFILES_DIR/tmux.conf"       "$HOME/.tmux.conf"
link "$DOTFILES_DIR/zellij-config.kdl" "$HOME/.config/zellij/config.kdl"
# iTerm2 is the exception: it stores prefs as a plist it rewrites itself, so it
# cannot be a symlink. steps/16-iterm2.sh points it at dotfiles/iterm2/ instead.

if [[ -d "$BACKUP_DIR" ]]; then
  warn "Replaced dotfiles were backed up to: $BACKUP_DIR"
fi
ok "Dotfiles linked"
