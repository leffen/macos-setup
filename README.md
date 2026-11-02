# macos-setup

One engineer's opinionated Mac setup, as a script: Homebrew and a Brewfile of
cloud, Kubernetes and security CLIs, language runtimes, oh-my-zsh, dotfiles, a
custom prompt, four terminals sharing one theme, SSH commit signing, and a few
macOS defaults that are not expressible in a config file.

It is a starting point, not a standard. Fork it, read the steps, keep what
fits. Works on **Apple Silicon** (`/opt/homebrew`) and **Intel**
(`/usr/local`); the architecture is detected automatically.

Nothing here needs an account or access to anything private. Clone it over
HTTPS and run it.

## Quick start

```sh
xcode-select --install          # once, on a fresh Mac; wait for the dialog to finish
git clone https://github.com/leffen/macos-setup.git ~/macos-setup
cd ~/macos-setup
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" ./setup.sh
```

`setup.sh` is **idempotent**: every step checks before it changes anything,
so it is safe to re-run. Existing dotfiles are moved to
`~/.dotfiles-backup-<date>/` before they are replaced.

It asks for `sudo` a few times (the Homebrew installer, Go into
`/usr/local/go`, the container `.pkg`, power settings), and step 12 asks for
your login password, which goes straight to `sysadminctl` to set the screen
lock. Run it from a terminal so those prompts can reach you.

## Options

Set these in the environment when you run `./setup.sh`. All are optional.

| Variable | Used by | Effect |
|---|---|---|
| `GIT_NAME`, `GIT_EMAIL` | step 18 | Your commit identity. Without them the step asks (in a terminal) or skips. |
| `SIGNING_KEY` | step 18 | Key path, default `~/.ssh/id_ed25519`. Created if missing. |
| `HOST_SHORT` | step 11 | Rename this Mac. Without it, nothing is renamed. |
| `INTERNAL_ZONES` | step 07 | Split DNS for a VPN or home network, e.g. `home.lan=192.168.1.1`. Without it, step 07 does nothing. |
| `INTERNAL_HOST` | `net-doctor.sh` | An internal name to test split DNS with. |

## What the steps do

`setup.sh` sources `steps/*.sh` in order. The numbers have gaps: the steps
missing from this public copy were specific to one person's machines.

| Step | Does |
|---|---|
| 00 | Xcode Command Line Tools |
| 01 | Homebrew, at the arch-aware prefix |
| 02 | Everything in the `Brewfile` |
| 03 | oh-my-zsh and its plugins |
| 04 | Go, Node (nvm), Python (pyenv), Rust, Bun, pnpm |
| 05 | Google Cloud SDK under `~/tools` |
| 06 | Symlinks the dotfiles (zsh, git, terminals, tmux, zellij) |
| 07 | Split-DNS resolver files, only with `INTERNAL_ZONES` |
| 09 | Rosetta 2, so arm64 Macs can run amd64 images |
| 10 | Apple's native container runtime |
| 11 | Host name, only with `HOST_SHORT`; refuses names that leak the serial |
| 12 | Power, screen saver and lock behaviour |
| 13 | `gh` and `tea` defaults |
| 14 | Pins github.com's SSH host keys, so a non-interactive `git` never hangs on the prompt |
| 16 | iTerm2 prefs from `dotfiles/iterm2/`, skipped if you have none there |
| 17 | Terminals in the Dock |
| 18 | SSH key for GitHub and commit signing, `~/.gitconfig.local`, `allowed_signers`, and a test signature |
| 19 | SSH server: public-key-only auth, plus a notification when someone logs in |
| 20 | Keeps your keys in ssh-agent across logins (login keychain + `~/.ssh/agent-keys`) |
| 21 | colima as the container engine, started at login |
| 22 | Azure CLI defaults and the `azl` login wrapper |
| 26 | Ghostty opens with one fresh window |

## After setup.sh

Secrets are never handled by the script. Finish these yourself:

- **GitHub:** add `~/.ssh/id_ed25519.pub` twice under Settings → SSH and GPG
  keys: once as an *Authentication* key, once as a *Signing* key. Without the
  second, GitHub shows your signed commits as "Unverified".
- `gh auth login`
- `gcloud auth login` and `gcloud auth application-default login`, if you use GCP
- `az login` (or `azl`), if you use Azure
- A SOPS age key in `~/.config/sops/age/keys.txt` (`chmod 600`), only if you
  decrypt sops files. `age-keygen -o ~/.config/sops/age/keys.txt` makes one.
- `exec zsh`, then `make verify`

## Your identity, and pushing over SSH

`dotfiles/gitconfig` holds no name, email or key: step 18 writes those to
`~/.gitconfig.local`, which it includes. So the dotfiles can be shared as they
are, and your fork does not have to carry your address.

GitHub stays on HTTPS by default. To push to an org over SSH, uncomment the
per-org `insteadOf` example in `dotfiles/gitconfig`. Do not rewrite all of
github.com: that breaks every Brewfile tap and plugin clone, and the comment
there explains how.

## make

`make` on its own lists every target.

| Target | Does |
|---|---|
| `make verify` | Tools present, dotfiles linked, and a real sign + verify with your key |
| `make keys` | Re-run step 18 (identity and signing key) |
| `make ssh-agent` | Re-run step 20 (keychain and agent manifest) |
| `make dotfiles` | Re-link the dotfiles only |
| `make lint` | shellcheck every script |
| `make brew` | Is the Brewfile satisfied? |
| `make disk` | What disk space could be reclaimed (dry run) |

## Tools

`scripts/tools/` holds a few standalone helpers:

- `net-doctor.sh` says what is actually wrong with this Mac's network:
  DNS, routes, TLS interception, endpoint security agents.
- `disk-cleanup.sh` finds reclaimable space (caches, old toolchains) without
  touching your data. Dry run unless you pass `--apply`.
- `install-tool.sh` installs an exact version (or the latest) of velero, flux,
  talosctl, kubectl or helm into `~/.local/bin`, checksum-verified, no sudo.
- `azl.sh` is `az login` without the noise.
- `fullscreen-awake.sh` holds off the idle lock while a fullscreen app is in front.
