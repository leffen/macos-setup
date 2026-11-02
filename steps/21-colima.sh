# steps/21-colima.sh — colima as the container engine, started at login
#
# Colima runs one Linux VM with a real Docker daemon, so `docker compose`,
# testcontainers and anything bind-mounting /var/run/docker.sock behave exactly
# as they do in CI. It replaces Docker Desktop, which this machine ran until
# 18 Sep 2026.
#
# Works on both architectures, unlike apple/container (arm64 only — see
# steps/10). On macOS 26 it uses Virtualization.framework even on Intel, not
# QEMU; `colima status` reports which. QEMU is still installed, but only to
# supply the binfmt emulators for cross-arch `--platform` builds.
#
# Runs after 02 (which installs colima and the docker CLI) and deliberately
# late, because it wants the whole Brewfile in place before starting a VM.
# Only instant steps follow it (22 az config, 23 ~/.local/bin links).
#
# Idempotent: re-running adopts a VM that is already up rather than recreating
# it, and never resizes one. Changing cpu/memory/disk on an existing VM needs
# an explicit `colima stop && colima start --cpu N ...`, which would discard
# nothing but is slow and surprising as a side effect of re-running setup.
#
# Unattended runs start nothing: booting a VM takes minutes and can prompt, and
# a step that hangs in CI is worse than one that is skipped. COLIMA_START=1 to
# force it, COLIMA_SKIP=1 to skip entirely.

log "Colima..."

COLIMA_CPU="${COLIMA_CPU:-4}"
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"
COLIMA_DISK="${COLIMA_DISK:-60}"

if [[ "${COLIMA_SKIP:-0}" == "1" ]]; then
  warn "colima skipped (COLIMA_SKIP=1)"
elif ! command -v colima >/dev/null 2>&1; then
  warn "colima not installed — run: brew bundle install --file=Brewfile"
else
  # ── 1. docker CLI plugins ───────────────────────────────────
  # compose and buildx are PLUGINS, and brew installs them outside docker's
  # default search path. Without cliPluginsExtraDirs, `docker compose` reports
  # "is not a docker command" while /usr/local/bin/docker-compose sits there
  # working — which reads as a broken compose rather than an unset path.
  #
  # Merged into the existing config, never rewritten: that file holds the
  # registry auth entries, and clobbering it would log you out of every
  # registry at once.
  DOCKER_CFG="$HOME/.docker/config.json"
  PLUGIN_DIR="$(brew --prefix)/lib/docker/cli-plugins"
  mkdir -p "$HOME/.docker"
  [[ -f "$DOCKER_CFG" ]] || echo '{}' > "$DOCKER_CFG"
  if python3 - "$DOCKER_CFG" "$PLUGIN_DIR" <<'PY'
import json, sys, shutil
cfg, plugin_dir = sys.argv[1], sys.argv[2]
try:
    with open(cfg) as fh:
        d = json.load(fh)
except (json.JSONDecodeError, OSError):
    sys.exit(2)          # malformed: say so rather than overwrite it
dirs = d.setdefault("cliPluginsExtraDirs", [])
if plugin_dir in dirs:
    sys.exit(1)          # already present: nothing to do
shutil.copy2(cfg, cfg + ".bak")
dirs.append(plugin_dir)
with open(cfg, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
  then
    ok "added $PLUGIN_DIR to cliPluginsExtraDirs (backup: ${DOCKER_CFG/#$HOME/~}.bak)"
  else
    case $? in
      1) ok "docker cli-plugins path already configured" ;;
      *) err "$DOCKER_CFG is not valid JSON — fix it by hand, leaving it alone" ;;
    esac
  fi

  # ── 2. the Docker Desktop credential store ──────────────────
  # Desktop sets "credsStore": "desktop", which resolves to a helper binary
  # INSIDE Docker.app. Remove Desktop without changing this and every
  # authenticated pull fails, with nothing saying why. Not rewritten here: the
  # credentials live in Desktop's own store and do not migrate, so flipping the
  # key logs you out of every registry at a moment of this script's choosing.
  # Warn, and let a human pick the moment.
  if [[ -f "$DOCKER_CFG" ]] && grep -q '"credsStore"[[:space:]]*:[[:space:]]*"desktop"' "$DOCKER_CFG"; then
    warn "~/.docker/config.json still has credsStore=desktop (a helper inside Docker.app)"
    warn "    uninstalling Docker Desktop with this set breaks every authenticated pull"
    warn "    switch to \"osxkeychain\" and re-run \`docker login\` per registry"
  fi

  # ── 3. start it, and keep it started ────────────────────────
  # `brew services` owns the LaunchAgent (RunAtLoad), so the VM comes back
  # after a reboot. The service runs bare `colima start -f` with NO flags: it
  # starts whatever the saved instance config says, which drives both of the
  # traps below.
  #
  # TRAP 1 — the sizing flags are for CREATION ONLY. Passing --disk to an
  # existing instance rewrites the saved config, and if the new value is
  # smaller lima refuses at every subsequent start with:
  #     Resize instance colima's disk from 100GiB to 60GiB
  #     disk shrinking is not supported
  # The VM then will not boot at all, including under launchd, and `colima
  # start` on its own cannot undo it -- the value is persisted in
  # ~/.colima/_lima/colima/colima.yaml and lima.yaml is regenerated from it, so
  # both have to be edited by hand to match the real diffdisk. That happened
  # here on 18 Sep 2026: a `--disk 60` against an existing 100GiB VM. So flags
  # are passed only when there is no instance yet.
  colima_instance_exists() { [[ -d "$HOME/.colima/_lima/colima" ]]; }

  # TRAP 2 — the service cannot adopt a VM that is already running. `colima
  # start -f` on a live instance logs "already running, ignoring" and exits 0;
  # launchd sees the process exit and the service goes straight back to
  # `stopped`, while every command still works because the standalone VM is up.
  # It looks fine and does not survive a reboot. Hence the state check at the
  # end rather than trusting the exit code of `brew services start`.
  colima_service_started() {
    brew services list 2>/dev/null | awk '$1 == "colima" { print $2 }' | grep -q '^started$'
  }

  if colima_service_started; then
    ok "colima running under brew services (starts at login)"
  elif [[ "${COLIMA_START:-0}" != "1" && ! -t 0 ]]; then
    warn "not a terminal; not booting a VM (COLIMA_START=1 to force)"
  else
    # A standalone VM has to come down first, or the service exits immediately.
    if colima status >/dev/null 2>&1; then
      log "stopping the standalone VM so brew services can own it..."
      colima stop >/dev/null 2>&1 || warn "colima stop failed — continuing"
    elif ! colima_instance_exists; then
      log "creating the VM (${COLIMA_CPU} cpu, ${COLIMA_MEMORY}G memory, ${COLIMA_DISK}G disk)..."
      colima start --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK" \
        >/dev/null 2>&1 || err "could not create the colima VM — run \`colima start\` to see why"
      colima stop >/dev/null 2>&1 || true
    fi

    log "starting colima via brew services..."
    brew services start colima >/dev/null 2>&1 || true

    # Poll for the daemon rather than assuming: a cold VM takes ~45s here, and
    # reporting success before the socket exists is how this step lied the
    # first time it was written.
    for _i in $(seq 1 24); do
      docker info >/dev/null 2>&1 && break
      /bin/sleep 5
    done

    if colima_service_started; then
      ok "colima running under brew services (starts at login)"
    else
      err "brew services reports colima as NOT started — it will not come back after a reboot"
      err "    check: brew services info colima; tail /usr/local/var/log/colima.log"
    fi
  fi

  # ── 3b. is there still a docker CLI at all? ─────────────────
  # Docker Desktop reclaims the /usr/local/bin paths it owns when it shuts
  # down, and it takes whatever occupies them with it -- including the Homebrew
  # symlinks that replaced its own. Killing Desktop on 18 Sep 2026 removed
  # docker, docker-compose and docker-credential-osxkeychain outright, leaving
  # `docker: command not found` on a machine where brew still reported the
  # formula as installed. docker-buildx survived, because Desktop never owned
  # that path.
  #
  # Worse, brew's link records still said "linked", so `brew link --overwrite`
  # answered "Already linked" and did nothing. The repair is unlink-then-link:
  #
  #   brew unlink docker && brew link --overwrite docker
  #
  # Expect this again after actually uninstalling Desktop.
  for _b in docker docker-compose docker-credential-osxkeychain; do
    command -v "$_b" >/dev/null 2>&1 && continue
    warn "$_b is missing from PATH — Docker Desktop most likely reclaimed its path"
    warn "    repair: brew unlink <formula> && brew link --overwrite <formula>"
  done
  unset _b

  # ── 4. point the docker CLI at it ───────────────────────────
  # Only when Desktop is not deliberately in charge: switching someone's active
  # context out from under them is exactly the kind of silent change this repo
  # keeps getting bitten by.
  if command -v docker >/dev/null 2>&1; then
    CURRENT_CTX="$(docker context show 2>/dev/null || true)"
    if [[ "$CURRENT_CTX" == "colima" ]]; then
      ok "docker context is colima"
    elif docker context use colima >/dev/null 2>&1; then
      ok "docker context switched from ${CURRENT_CTX:-unknown} to colima"
    else
      warn "could not select the colima docker context (was: ${CURRENT_CTX:-unknown})"
    fi
  fi

  # ── 5. /var/run/docker.sock ─────────────────────────────────
  # The docker CLI follows its context, but plenty of things never ask:
  # testcontainers, IDE docker integrations, and anything that hard-codes the
  # socket path. They want /var/run/docker.sock. Docker Desktop kept that
  # pointing at itself; once it is gone the link dangles at
  # ~/.docker/run/docker.sock and those tools fail with "connection refused"
  # while `docker ps` works fine. Found that way on 1 Nov 2026.
  #
  # A one-off `ln` is not enough: macOS empties /var/run at every boot. On
  # 31 Oct everything in it dated from the boot minute, Desktop's link from the
  # minute after, recreated by its own root helper. So this installs the same
  # kind of helper: a LaunchDaemon that runs `ln -sfn` at load. Pointing at
  # colima's socket before the VM is up is harmless; the link just dangles
  # until colima creates it.
  #
  # Desktop's com.docker.socket daemon, if still installed, re-points the link
  # at Desktop on boot, so warn about it rather than race it.
  SOCK_LINK="/var/run/docker.sock"
  SOCK_TARGET="$HOME/.colima/default/docker.sock"
  SOCK_LABEL="com.macos-setup.docker-sock"
  SOCK_PLIST="/Library/LaunchDaemons/$SOCK_LABEL.plist"
  SOCK_PLIST_BODY="$(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Managed by macos-setup (steps/21-colima.sh) -->
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$SOCK_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/ln</string><string>-sfn</string>
    <string>$SOCK_TARGET</string><string>$SOCK_LINK</string>
  </array>
  <key>RunAtLoad</key>        <true/>
</dict>
</plist>
PLIST
)"

  if [[ -f /Library/LaunchDaemons/com.docker.socket.plist ]]; then
    warn "Docker Desktop's com.docker.socket daemon is still installed; it re-points"
    warn "    $SOCK_LINK at Desktop on boot. Once Desktop is gone, remove it:"
    warn "        sudo launchctl bootout system/com.docker.socket"
    warn "        sudo rm /Library/LaunchDaemons/com.docker.socket.plist /Library/PrivilegedHelperTools/com.docker.socket"
  fi

  if [[ "$(readlink "$SOCK_LINK" 2>/dev/null)" == "$SOCK_TARGET" \
        && "$(cat "$SOCK_PLIST" 2>/dev/null)" == "$SOCK_PLIST_BODY" ]]; then
    ok "$SOCK_LINK -> colima (re-created at boot by $SOCK_LABEL)"
  elif [[ -t 0 ]] || sudo -n true 2>/dev/null; then
    log "pointing $SOCK_LINK at colima, and keeping it there across reboots (sudo)..."
    if printf '%s\n' "$SOCK_PLIST_BODY" | sudo tee "$SOCK_PLIST" >/dev/null \
        && sudo chown root:wheel "$SOCK_PLIST" && sudo chmod 644 "$SOCK_PLIST" \
        && sudo ln -sfn "$SOCK_TARGET" "$SOCK_LINK"; then
      sudo launchctl bootout "system/$SOCK_LABEL" >/dev/null 2>&1 || true
      if sudo launchctl bootstrap system "$SOCK_PLIST" >/dev/null 2>&1; then
        ok "$SOCK_LINK -> colima (re-created at boot by $SOCK_LABEL)"
      else
        warn "$SOCK_LINK -> colima now, but $SOCK_LABEL did not load; it will not survive a reboot"
      fi
    else
      err "could not point $SOCK_LINK at colima"
    fi
  elif [[ "$(readlink "$SOCK_LINK" 2>/dev/null)" == "$SOCK_TARGET" ]]; then
    warn "$SOCK_LINK -> colima, but nothing re-creates it at boot ($SOCK_LABEL missing)"
    warn "    not a terminal, and installing it needs sudo: re-run this step in a terminal"
  else
    warn "not a terminal; $SOCK_LINK points at $(readlink "$SOCK_LINK" 2>/dev/null || echo nothing), not colima"
    warn "    fixing it needs sudo: re-run this step in a terminal"
  fi
fi

unset COLIMA_CPU COLIMA_MEMORY COLIMA_DISK DOCKER_CFG PLUGIN_DIR CURRENT_CTX _i
unset SOCK_LINK SOCK_TARGET SOCK_LABEL SOCK_PLIST SOCK_PLIST_BODY
unset -f colima_instance_exists colima_service_started 2>/dev/null || true

ok "Colima checked"
