# Brewfile — managed by macos-setup
# Installed via:  brew bundle --file=Brewfile
# Captures every formula from `brew leaves` plus casks.

# ── Taps ──────────────────────────────────────────────────────
tap "azure/kubelogin"
tap "fluxcd/tap"
tap "hashicorp/tap"
tap "nklmilojevic/sofka"
tap "terraform-linters/tap"

# ── Core CLI ──────────────────────────────────────────────────
brew "git"
brew "git-filter-repo"
brew "make"                # GNU Make 4.x; macOS ships 3.81 (2006)
brew "gh"
brew "tea"                 # Gitea CLI
brew "watch"
brew "yq"
brew "nmap"
brew "poppler"
brew "qemu"
brew "zoxide"              # the modern z: `z proj` jumps, `zi` picks interactively
brew "fzf"                 # ctrl-r history, ctrl-t files, alt-c cd

# ── Modern replacements (aliased over the originals in aliases.zsh) ──
brew "eza"                 # ls
brew "bat"                 # cat
brew "ripgrep"             # grep
brew "fd"                  # find
brew "git-delta"           # git diff (wired up as core.pager in dotfiles/gitconfig)

# ── Cloud / Kubernetes ────────────────────────────────────────
# Google Cloud is deliberately absent here: steps/05-gcloud.sh installs the
# SDK tarball under ~/tools instead, and dotfiles/zshrc sources its own
# path/completion .inc files. Adding google-cloud-sdk to this file would put
# a second gcloud on PATH, shadowing the one those .inc files configure.
brew "awscli"             # v2 in Homebrew; `aws` is not on PATH without it
# azure-cli moved from homebrew-core to homebrew-cask in Oct 2026. The old
# `brew "azure-cli"` now resolves to nothing -- see the tflint note below.
cask "azure-cli"
brew "azure/kubelogin/kubelogin"
brew "doctl"
brew "fluxcd/tap/flux"
brew "govc"
brew "helm"
brew "k9s"
brew "nklmilojevic/sofka/sofka"  # k9s alternative; reads Flux and Helm state
                                 # directly, so no flux binary needed to suspend
                                 # or reconcile from the TUI
brew "kubectx"
brew "kubernetes-cli"
brew "kustomize"
brew "kube-ps1"            # sourced by the kube-ps1 oh-my-zsh plugin / prompt
brew "stern"               # multi-pod log tailing
# homebrew/core carries talosctl at the same version the vendor tap does
# (both 1.13.8 on 13 Sep), so the tap earned nothing and cost a third-party
# tap trusted to run its own code at install time. Homebrew 7 refuses
# untrusted taps outright, which is what surfaced this.
brew "talosctl"
brew "skopeo"
# testkube is deliberately NOT a brew line. lz-dev.k8s/scripts/testkube-oss/tk.sh
# refuses to run without it, but Homebrew stopped bottling for Intel x86_64
# (announced Aug 2025, in force Sep 2026), so `brew install testkube` builds from
# source: it pulls go@1.26, bash, texinfo and coreutils, upgrades helm and
# kubernetes-cli as a side effect, and takes about an hour. The formula is also
# ahead of the vendor's releases -- it offered 2.14.1 while the newest GitHub
# release was 2.14.0. Install the release binary instead, which matches the agent
# version running on stage:
#
#   V=2.14.0
#   gh release download "$V" --repo kubeshop/testkube \
#     --pattern "testkube_${V}_Darwin_x86_64.tar.gz" --pattern checksums.txt
#   shasum -a 256 -c checksums.txt --ignore-missing
#   tar -xzf "testkube_${V}_Darwin_x86_64.tar.gz" kubectl-testkube
#   install -m 0755 kubectl-testkube ~/.local/bin/testkube
#   ln -sf ~/.local/bin/testkube ~/.local/bin/kubectl-testkube
brew "velero"

# ── Local Kubernetes / cluster dev ────────────────────────────
brew "kind"
brew "k3d"
brew "skaffold"
brew "krew"                # kubectl plugin manager; PATH wired in dotfiles/zshrc
brew "kubeseal"
brew "argocd"
brew "dive"                # inspect image layers
brew "kubecolor"           # colourises kubectl; passes through untouched when piped
brew "popeye"              # cluster sanity scan

# ── Containers ────────────────────────────────────────────────
# Two stacks, deliberately side by side — they do not conflict, because each
# owns a different Docker context (`colima` vs `socktainer`).
#
# 1. colima: one shared Linux VM running a real Docker daemon. This is the
#    compatible option — `docker compose` and testcontainers behave exactly as
#    they do in CI.
brew "colima"
brew "docker"             # CLI only; colima (or socktainer) supplies the engine
brew "docker-compose"     # a PLUGIN, not a binary: needs cliPluginsExtraDirs in
brew "docker-buildx"      # ~/.docker/config.json, or `docker compose` and
                          # `docker buildx` are simply not found. steps/21 sets it.
# Supplies docker-credential-osxkeychain. Docker Desktop sets
# "credsStore": "desktop" in ~/.docker/config.json, pointing at a helper INSIDE
# Docker.app -- uninstall Desktop without switching that key to "osxkeychain"
# and every authenticated registry pull fails, with nothing warning you.
brew "docker-credential-helper"
#
# 2. Apple's container: each container gets its own lightweight VM. Faster to
#    start and better isolated, but it speaks its own API, not Docker's — hence
#    the two shims. Needs Apple silicon + macOS 26 for usable networking.
#    steps/10-apple-container.sh sets it up once installed.
#
#    The Apple-silicon requirement is a HARD one and is now enforced rather
#    than written down. apple/container ships an arm64-only binary: on an Intel
#    Mac it installs cleanly and then every invocation dies with
#      bad CPU type in executable: container
#    which names no cause and does not mention architecture at all. This block
#    was unguarded until 18 Sep 2026, so the Mac Pro (Xeon W-3245) installed all
#    three every run and `container` was broken the whole time. steps/10 carries
#    the matching guard.
if Hardware::CPU.arm?
  brew "container"
  brew "container-compose" # runs docker-compose.yml files; NOTE: starts services
                           # one at a time, so multi-service stacks are unreliable
  brew "socktainer"        # Docker-compatible REST API in front of `container`;
                           # this is what makes testcontainers work
end

# ── Infrastructure as code ────────────────────────────────────
brew "hashicorp/tap/packer"
# terraform deliberately absent: tfenv provides the `terraform` shim, and only
# one of them can own <brew-prefix>/bin/terraform. tfenv wins because it honours
# the .terraform-version files some repos carry, and installs the pinned version
# on demand -- brew gives whatever it has today, which is the wrong version for
# a repo pinned to an old one.
#
# Absent from this file is NOT the same as absent from the machine. A brew
# terraform installed before this decision keeps the symlink, and then tfenv
# cannot link -- `brew bundle check` says only "tfenv needs to be linked",
# which does not sound like a conflict with a package that is no longer
# declared. That state survived here from April to September 2026: terraform
# worked (brew's), tfenv was never linked, so `tfenv` itself was
# command-not-found while `terraform --version` answered perfectly.
#
# If check reports tfenv unlinked:
#   brew unlink terraform && brew link tfenv
#   brew uninstall terraform          # optional, it is drift either way
#   tfenv install latest && tfenv use latest
#
# Until a version is selected, `terraform` fails with "Version could not be
# resolved", which does not obviously point at tfenv either.
brew "tfenv"              # provides `terraform`
# tflint ships as a cask in its tap, not a formula. It was listed here as a
# bare `brew "tflint"`, which resolves to nothing in homebrew-core -- so this
# line aborted the whole `brew install` invocation and every formula after it
# was skipped, which is why step 02 quietly left six things uninstalled.
cask "terraform-linters/tap/tflint"

# ── Security ──────────────────────────────────────────────────
brew "gitleaks"
brew "sops"
brew "trivy"

# ── Languages / tooling ───────────────────────────────────────
brew "shellcheck"        # `make lint`; was installed here but not listed
brew "pyenv"             # Python versions; runtime installed in steps/04
brew "uv"

# ── Terminals & multiplexers ──────────────────────────────────
# Four emulators is deliberate, not accumulation: ghostty is the daily driver,
# the others are here to be compared on equal terms. All four share one font
# and one palette (Vesper) via dotfiles/, so a comparison is about the terminal
# rather than the theme. tmux and zellij are the two session-survival answers
# that are not WezTerm's mux domain.
brew "tmux"
brew "zellij"
cask "kitty"
cask "wezterm"
brew "dockutil"           # steps/17-dock.sh puts the terminals in the Dock;
                          # the raw `defaults write persistent-apps` form
                          # appends duplicates on every re-run

# ── Casks ─────────────────────────────────────────────────────
cask "codex"
cask "ghostty"
cask "font-geist-mono"   # font-family in dotfiles/ghostty-config
cask "iterm2"

# ── Editors & AI tooling ──────────────────────────────────────
cask "claude-code"
cask "claude"
cask "vscodium"
cask "antigravity"
