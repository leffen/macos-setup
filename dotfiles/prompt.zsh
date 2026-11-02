# ~/.config/zsh/prompt.zsh — managed by macos-setup
# Custom two-line prompt: user + kube context + cwd, then ruby/git/venv info.
# Relies on the oh-my-zsh `kube-ps1` plugin, and on git_prompt_info from omz's
# lib/git.zsh — made synchronous in ~/.zshrc, read the comment there.

PROMPT='╭─%{$terminfo[bold]$fg[green]%}%n $(kube_ps1) %{$reset_color%}%{$terminfo[bold]$fg[blue]%}%~ %{$reset_color%}$(ruby_prompt_info)$(git_prompt_info)$(virtualenv_prompt_info)
╰─%B$%b '
