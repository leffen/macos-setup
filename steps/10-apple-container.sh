# steps/10-apple-container.sh — Apple's native container runtime
#
# apple/container ships as a signed .pkg rather than a formula, so this
# resolves the latest release itself. Needs macOS 26+; skipped below that.
#
# The signature check before `installer` is deliberate and must stay: this
# downloads an executable package over the network and hands it to root. If
# the signature is not from a Developer ID Installer certificate we refuse
# rather than warn — an unverified root install is not a degraded mode.

CONTAINER_FALLBACK_VERSION=1.3.1

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
# Architecture first, because it is the harder requirement and the one that
# used to be missing. apple/container is an arm64-only binary and the .pkg
# installs happily on Intel -- the failure comes later, at every single
# invocation, as:
#
#   bad CPU type in executable: container
#
# which names no cause, does not say "architecture", and reads like a corrupt
# download. This step gated on macOS 26 but not on the CPU, so the Mac Pro
# (Xeon W-3245, macOS 26.6.2) passed the gate and reinstalled a binary it could
# never run on every setup. Found 18 Sep 2026. The Brewfile carries the
# matching guard for container-compose and socktainer, which front this tool
# and are equally useless without it.
#
# arch -arm64 is not a way out: Rosetta translates x86 on arm, never arm on x86.
CPU_ARCH="$(uname -m)"
if [[ "$CPU_ARCH" != "arm64" ]]; then
  warn "Apple container needs Apple silicon (this is $CPU_ARCH) — skipping"
  warn "    on Intel use colima (steps/21-colima.sh)"
elif [[ "$MACOS_MAJOR" -lt 26 ]]; then
  warn "Apple container needs macOS 26 or newer (this is $(sw_vers -productVersion)) — skipping"
else
  log "Resolving the latest release from github.com/apple/container..."
  CV="$(curl -fsSL --max-time 20 https://api.github.com/repos/apple/container/releases/latest 2>/dev/null \
        | tr ',' '\n' | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)"
  if [[ -z "${CV:-}" ]]; then
    CV="$CONTAINER_FALLBACK_VERSION"
    warn "could not reach the GitHub API — falling back to $CV"
  fi

  INSTALLED_V=""
  if command -v container >/dev/null 2>&1; then
    INSTALLED_V="$(container --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  fi

  if [[ "$INSTALLED_V" == "$CV" ]]; then
    ok "container $CV already installed"
  else
    [[ -n "$INSTALLED_V" ]] && log "Upgrading container $INSTALLED_V -> $CV" || log "Installing container $CV"
    PKG_DIR="$(mktemp -d)"
    PKG="$PKG_DIR/container-$CV-installer-signed.pkg"
    URL="https://github.com/apple/container/releases/download/$CV/container-$CV-installer-signed.pkg"

    if ! curl -fL --progress-bar -o "$PKG" "$URL"; then
      rm -rf "$PKG_DIR"
      err "download failed: $URL"
      return 1 2>/dev/null || exit 1
    fi

    log "Verifying the package signature..."
    if pkgutil --check-signature "$PKG" | grep -qi 'Developer ID Installer'; then
      ok "signed by a Developer ID Installer certificate"
    else
      pkgutil --check-signature "$PKG" || true
      rm -rf "$PKG_DIR"
      err "package signature not recognised — refusing to install."
      return 1 2>/dev/null || exit 1
    fi

    if sudo installer -pkg "$PKG" -target /; then
      rm -rf "$PKG_DIR"
      hash -r
      ok "container installed"
    else
      rm -rf "$PKG_DIR"
      err "installer failed."
      return 1 2>/dev/null || exit 1
    fi
  fi

  export PATH="/usr/local/bin:$PATH"
  if container system status >/dev/null 2>&1; then
    ok "container service already running"
  elif [[ -t 0 ]]; then
    # First start may offer to fetch a Linux kernel, which needs an answer.
    log "Starting the container service (it may offer to fetch a Linux kernel — say yes)..."
    if container system start < /dev/tty; then
      ok "container service started"
    else
      warn "could not start the service — run 'container system start' yourself"
    fi
  else
    warn "no tty — start the service yourself with: container system start"
  fi
fi
