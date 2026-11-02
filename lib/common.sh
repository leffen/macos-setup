# lib/common.sh — shared helpers (sourced by setup.sh and every step)

set -euo pipefail

# ── Logging ───────────────────────────────────────────────────
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  \xe2\x9c\x93\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m  \xe2\x9c\x97\033[0m %s\n' "$*" >&2; }

# ── Architecture detection ────────────────────────────────────
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"   # Apple Silicon
  GO_ARCH="arm64"
  GCLOUD_ARCH="arm"
else
  BREW_PREFIX="/usr/local"      # Intel
  GO_ARCH="amd64"
  GCLOUD_ARCH="x86_64"
fi
BREW_BIN="$BREW_PREFIX/bin/brew"

# ── Paths ─────────────────────────────────────────────────────
# BASH_SOURCE is empty under zsh, and this file is sourced often enough by hand
# that "run it in the wrong shell" is a real case, not a hypothetical. When it
# is empty REPO_ROOT becomes "", DOTFILES_DIR becomes "/dotfiles", and step 06
# then links every dotfile to a path that does not exist. That happened on
# 16 Aug: eight dotfiles replaced with dangling symlinks in one command.
#
# So resolve it defensively and refuse to continue if the answer is not
# obviously this repo. A wrong REPO_ROOT is not a degraded mode -- it is the
# destructive one.
_common_self="${BASH_SOURCE[0]:-$0}"
REPO_ROOT="$(cd "$(dirname "$_common_self")/.." 2>/dev/null && pwd)"
if [[ -z "${REPO_ROOT:-}" || ! -d "$REPO_ROOT/dotfiles" || ! -f "$REPO_ROOT/setup.sh" ]]; then
  printf '\033[1;31m  \xe2\x9c\x97\033[0m %s\n' \
    "lib/common.sh: REPO_ROOT resolved to '${REPO_ROOT:-}', which is not this repo." >&2
  printf '     %s\n' "Run ./setup.sh, or source this from bash rather than zsh." >&2
  return 1 2>/dev/null || exit 1
fi
unset _common_self
DOTFILES_DIR="$REPO_ROOT/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# ── Machine identity, and keeping the serial out of what we publish ──
# The hardware serial identifies this machine, and two things here write a
# machine name into somewhere public: the hostnames registry (tracked and
# mirrored) and the comment on a signing key (uploaded to GitHub and Gitea
# with the key, and not recallable afterwards). Neither may carry the serial.
#
# These live here rather than in steps/11-hostname.sh because `make keys` runs
# step 18 on its own, sourcing only this file -- a guard defined in step 11
# would simply not exist for the path that publishes to a forge.
#
# MACHINE_SERIAL and MACHINE_ID override the real values, which is what makes
# any of this testable without a second Mac.
machine_serial() {
  local _serial
  if [[ -n "${MACHINE_SERIAL:-}" ]]; then
    printf '%s' "$MACHINE_SERIAL"
    return 0
  fi
  _serial="$(ioreg -c IOPlatformExpertDevice -d 2 2>/dev/null \
             | awk -F'"' '/IOPlatformSerialNumber/{print $4; exit}')"
  [[ -n "$_serial" ]] || return 1
  printf '%s' "$_serial"
}

machine_id() {
  local _serial
  if [[ -n "${MACHINE_ID:-}" ]]; then
    printf '%s' "$MACHINE_ID"
    return 0
  fi
  _serial="$(machine_serial)" || return 1
  printf '%s' "$_serial" | shasum -a 256 | cut -c1-12
}

# How many CONSECUTIVE characters of the serial a name may not contain.
#
# The first version of this guard asked whether the name contained the WHOLE
# serial, and that is not how an MDM builds a name. Intune named this machine
# corpmac-<serial minus its first character>: 9 of 10 characters, so the check
# passed and the name was treated as ordinary. Every reason the guard exists
# applied, and none of it fired.
#
# 8 is chosen because an Apple serial is 10-12 characters. A name would have
# to reproduce 8 consecutive characters of THIS machine's serial by accident
# to trip it, while any name actually built from the serial is caught even if
# the MDM trims or reorders a character or two.
SERIAL_MIN_RUN="${SERIAL_MIN_RUN:-8}"

# Unknown serial returns false: nothing can be compared, so nothing is claimed.
# Callers treat a false here as "no evidence", never as "proven safe".
name_leaks_serial() {
  local _s _n _min _len _i _sub
  _s="$(machine_serial 2>/dev/null)" || return 1
  [[ -n "$_s" ]] || return 1
  _n="${1:-}"
  [[ -n "$_n" ]] || return 1
  _s="$(printf '%s' "$_s" | tr '[:upper:]' '[:lower:]')"
  _n="$(printf '%s' "$_n" | tr '[:upper:]' '[:lower:]')"

  _len=${#_s}
  _min="${SERIAL_MIN_RUN:-8}"
  # A serial shorter than the threshold is compared whole, rather than never.
  if (( _min > _len )); then _min=$_len; fi
  if (( _min <= 0 )); then return 1; fi

  for (( _i = 0; _i + _min <= _len; _i++ )); do
    _sub="${_s:_i:_min}"
    if [[ "$_n" == *"$_sub"* ]]; then return 0; fi
  done
  return 1
}

# ── Put Homebrew on PATH if it is installed ───────────────────
ensure_brew() {
  if [[ -x "$BREW_BIN" ]]; then
    eval "$("$BREW_BIN" shellenv)"
  fi
}

# ── Is the network actually usable? ───────────────────────────
# Resolution and reachability are one check here but two different failures,
# and the one that matters is DNS. On 13 Sep a Cloudflare WARP reconnect took
# the resolver at 127.0.2.2 down in the middle of `brew bundle`: the link was
# up, the Wi-Fi icon was full, `ping 1.1.1.1` would have answered, and every
# single download died with "Could not resolve host: ghcr.io". Anything that
# probes connectivity by pinging an IP would have reported a healthy network
# throughout.
#
# So resolution is checked through dscacheutil, which asks the same system
# resolver curl will use, rather than by querying a nameserver directly --
# `dig @1.1.1.1` succeeds happily while the resolver curl uses is dead.
net_ok() {
  local host="${1:-ghcr.io}"
  if ! dscacheutil -q host -a name "$host" 2>/dev/null | grep -q '_address:'; then
    return 1
  fi
  # No -f: any HTTP status at all means the connection was made, which is the
  # whole question. -f would turn ghcr.io's 404 on / into a false alarm.
  curl -s -o /dev/null --max-time 10 "https://$host"
}

# ── Symlink a file, backing up anything already there ─────────
link() {
  local src="$1" dest="$2"
  # Never replace a real file with a link to something that does not exist.
  # ln -s is happy to create a dangling symlink, and the backup happens first,
  # so a bad src silently trades a working dotfile for a broken one. This guard
  # alone would have prevented the 16 Aug incident described above.
  if [[ ! -e "$src" ]]; then
    err "refusing to link $dest -> $src (source does not exist)"
    return 1
  fi
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    ok "$dest already linked"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dest" "$BACKUP_DIR/"
    warn "backed up existing $dest -> $BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  ok "linked $dest -> $src"
}
