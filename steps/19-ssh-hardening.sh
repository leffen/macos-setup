# steps/19-ssh-hardening.sh — SSH: public-key-only auth + login alert
#
# 1. Disables password / keyboard-interactive auth (key-based login only).
# 2. Pops a macOS notification (with sound) whenever an SSH session opens.
#
# How the alert works (macOS has no pam_exec):
#   /etc/ssh/sshrc runs on EVERY ssh session as the connecting user and
#   appends an event to a spool file. A per-user LaunchAgent watches that
#   file and — running inside your GUI (Aqua) session — shows the
#   notification. Only the GUI session can reliably display one.
#
# It reports a session being OPENED with a key that is already trusted, which
# file-integrity tools watching authorized_keys do not see.
#
# Safety: the lockout risk exists only while sshd is actually reachable, so
# that is what is checked first. With Remote Login OFF there is no session to
# lock out of and the drop-in is installed unconditionally -- which means SSH
# is already key-only on the day Remote Login is switched on. With it ON, a
# usable authorized_keys is required before passwords are disabled.
#
# Config changes apply to NEW connections only (launchd spawns sshd per
# connection), so your current session is never dropped.

DROPIN="/etc/ssh/sshd_config.d/010-hardening.conf"
SSHRC="/etc/ssh/sshrc"
SPOOL="/Users/Shared/.ssh-login-events"
NOTIFY="/usr/local/sbin/ssh-login-notify.sh"
AGENT="$HOME/Library/LaunchAgents/com.macos-setup.ssh-login-alert.plist"
AGENT_LABEL="com.macos-setup.ssh-login-alert"

# ── Is sshd actually reachable? ───────────────────────────────
# `systemsetup -getremotelogin` would answer this but needs sudo, and this
# runs before any other sudo in the step. A listener probe needs none and
# answers the question that matters: can anyone connect right now.
_ssh_remote_login_on() {
  netstat -an 2>/dev/null \
    | awk '$1 ~ /^tcp/ && $NF == "LISTEN" && $4 ~ /\.22$/ { found = 1 } END { exit !found }'
}

# ── Safety: make sure key auth will actually work first ───────
have_keys=0
for f in "$HOME/.ssh/authorized_keys" /var/root/.ssh/authorized_keys; do
  if [[ -f "$f" ]] && grep -qE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$f"; then
    have_keys=1
  fi
done

if [[ "$have_keys" -ne 1 ]]; then
  if _ssh_remote_login_on; then
    # Someone can connect right now, and disabling passwords without a key on
    # file would end that for good. This is the one case that must stop.
    err "Remote Login is ON and there is no usable key in ~/.ssh/authorized_keys."
    err "Refusing to disable password auth — it would lock you out."
    err "Add your public key first, e.g.:  pbpaste >> ~/.ssh/authorized_keys"
    return 0 2>/dev/null || exit 0
  fi
  # Nothing is listening, so there is no session to lose. Hardening now is
  # strictly better than hardening later: it is in place before the first
  # connection is ever possible.
  warn "Remote Login is off — hardening anyway, so SSH is key-only if you enable it."
  warn "    BUT there is no ~/.ssh/authorized_keys, and this disables passwords."
  warn "    Add a key BEFORE turning Remote Login on, or nothing will get in:"
  warn "        pbpaste >> ~/.ssh/authorized_keys"
fi

# ── 1. Harden sshd: public-key only ───────────────────────────
sudo tee "$DROPIN" >/dev/null <<'CONF'
# Managed by macos-setup (steps/19-ssh-hardening.sh)
# Public-key authentication only — passwords are disabled.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
AuthenticationMethods publickey
CONF
sudo chmod 644 "$DROPIN"
ok "wrote $DROPIN (key-only auth)"

# ── 2. sshrc: record every session (runs as the connecting user) ──
sudo tee "$SSHRC" >/dev/null <<'SH'
#!/bin/sh
# Managed by macos-setup. Runs on every SSH session.
spool="/Users/Shared/.ssh-login-events"
from="${SSH_CONNECTION%% *}"
when="$(date '+%Y-%m-%d %H:%M:%S')"
who="$(id -un)"
logger -t ssh-login-alert "SSH login: user=$who from=${from:-?} at $when"
printf '%s|%s|%s\n' "$when" "$who" "${from:-?}" >> "$spool" 2>/dev/null || true
SH
sudo chmod 644 "$SSHRC"
# Spool must be appendable by any connecting user; created if missing.
sudo touch "$SPOOL"
sudo chmod 666 "$SPOOL"
ok "installed $SSHRC + spool $SPOOL"

# ── 3. Notifier (runs inside the GUI session via the LaunchAgent) ──
sudo mkdir -p "$(dirname "$NOTIFY")"
sudo tee "$NOTIFY" >/dev/null <<'SH'
#!/bin/sh
# Managed by macos-setup. Shows a notification for the latest login.
spool="/Users/Shared/.ssh-login-events"
[ -f "$spool" ] || exit 0
last="$(tail -n 1 "$spool")"
[ -n "$last" ] || exit 0
when="${last%%|*}"; rest="${last#*|}"; who="${rest%%|*}"; from="${rest#*|}"
osascript -e "display notification \"$who from $from\" with title \"⚠️ SSH login\" subtitle \"$when\" sound name \"Sosumi\"" >/dev/null 2>&1
SH
sudo chmod 755 "$NOTIFY"
ok "installed notifier $NOTIFY"

# ── 4. LaunchAgent: watch the spool, notify in the GUI session ──
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$AGENT_LABEL</string>
  <key>ProgramArguments</key> <array><string>$NOTIFY</string></array>
  <key>WatchPaths</key>       <array><string>$SPOOL</string></array>
  <key>RunAtLoad</key>        <false/>
</dict>
</plist>
PLIST
ok "wrote LaunchAgent $AGENT"

# Reload the agent (idempotent).
uid="$(id -u)"
launchctl bootout "gui/$uid/$AGENT_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$AGENT" >/dev/null 2>&1 \
  || launchctl load "$AGENT" >/dev/null 2>&1 || true
ok "login-alert agent loaded"

# ── 5. Validate ───────────────────────────────────────────────
if sudo /usr/sbin/sshd -t; then
  ok "sshd config valid — applies to NEW connections (no restart, current session safe)"
else
  err "sshd -t reported an error — review $DROPIN BEFORE disconnecting!"
fi
warn "First notification may be silent until you allow notifications for 'Script Editor' in System Settings."
