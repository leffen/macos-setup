# steps/11-hostname.sh — name this machine, at most one machine per name
#
# There is deliberately NO default name. This step used to default to `oldmac`,
# which meant every fresh Mac bootstrapped by this repo claimed the same name
# unless someone remembered `HOST_SHORT=`. The backstop was a single
# `ping oldmac.local`, which cannot see a machine that is asleep, on another
# network, or retired -- and "retired" is the case that actually happened:
# `oldmac` was a previous machine's name, inherited by this one.
#
# The consequence is bigger than mDNS. steps/18-git-signing-keys.sh stamps each
# signing key with `-C "<identity>@$(hostname -s)"`, and the whole per-machine
# key design rests on that comment telling you WHICH machine to revoke at the
# forge. Two machines called oldmac produce two keys labelled personal@oldmac.
#
# So a name is claimed, once, in a tracked registry:
#
#     HOST_SHORT=kaito ./setup.sh
#
# Without HOST_SHORT nothing is renamed. A machine keeps whatever name it has
# until it is named deliberately -- an ugly unique name beats a shared one.

HOSTNAME_REGISTRY="${HOSTNAME_REGISTRY:-$REPO_ROOT/hostnames}"

# ── Machine identity ──────────────────────────────────────────
# machine_serial, machine_id and name_leaks_serial live in lib/common.sh: the
# serial must also stay out of the signing-key comments step 18 publishes, and
# `make keys` runs that step sourcing only lib/common.sh. One guard, one place.
#
# The serial is hashed before it is written down, because the registry is
# tracked and mirrored and a raw serial is a real device identifier that
# warranty and support lookups key on. MACHINE_ID and MACHINE_SERIAL override
# both, which is what makes this testable without a second Mac.
#
# A name carrying this machine's serial would put in the NAME column exactly
# what the machine-id column hashes to keep out. This machine is enrolled in
# Intune, and `corpmac-<serial>` is the kind of convention an MDM enforces -- so
# the name can change under this step without anyone running it, and the next
# run would adopt it into a tracked, mirrored file.
#
# Unknown serial means nothing can be compared, so nothing is claimed to leak.
# The comparison itself is name_leaks_serial in lib/common.sh, which matches a
# RUN of the serial rather than the whole of it -- this machine's MDM name
# carries 9 of its 10 characters, which a whole-serial test waves through.

# ── Registry lookups ──────────────────────────────────────────
# Format: one line per machine, "name  machine-id  claimed-date". A name is
# claimed if and only if a line exists, so retiring a machine is deleting its
# line -- there is no status column and no lifecycle to keep straight.
_hn_claimant() {   # name -> the machine-id holding it, or nothing
  [[ -f "$HOSTNAME_REGISTRY" ]] || return 0
  awk -v n="$1" '!/^[[:space:]]*#/ && NF>=2 && $1==n {print $2; exit}' \
    "$HOSTNAME_REGISTRY"
}

_hn_name_of() {    # machine-id -> the name it holds, or nothing
  [[ -f "$HOSTNAME_REGISTRY" ]] || return 0
  awk -v i="$1" '!/^[[:space:]]*#/ && NF>=2 && $2==i {print $1; exit}' \
    "$HOSTNAME_REGISTRY"
}

# Names Apple gives a Mac out of the box. Adopting one of these would claim
# "MacBook-Pro" for a machine and then refuse it to the next one, which is the
# original bug wearing a different hat.
_hn_is_factory_name() {
  local _n
  _n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$_n" in
    ''|mac|imac|macbook|macmini|macstudio|macpro) return 0 ;;
    *macbook*|*imac*|*mac-mini*|*mac-studio*|*mac-pro*|*-mac|mac-*) return 0 ;;
  esac
  return 1
}

# Rewrite this machine's line, dropping any earlier one it held. Keeping one
# line per machine-id is what releases the old name when a machine is renamed.
_hn_claim() {      # name id
  local _tmp
  _tmp="$(mktemp)"
  if [[ -f "$HOSTNAME_REGISTRY" ]]; then
    awk -v i="$2" '/^[[:space:]]*#/ || NF<2 || $2!=i' "$HOSTNAME_REGISTRY" > "$_tmp"
  else
    {
      echo "# Which machine holds which host name. Tracked so that two machines"
      echo "# cannot end up with the same name -- see steps/11-hostname.sh."
      echo "#"
      echo "# machine-id is sha256(hardware serial), first 12 chars. The serial"
      echo "# itself is deliberately not recorded: this file is mirrored."
      echo "#"
      echo "# Retiring a machine? Delete its line. That frees the name."
      echo "#"
      echo "# name             machine-id      claimed"
    } > "$_tmp"
  fi
  printf '%-18s %-15s %s\n' "$1" "$2" "$(date +%F)" >> "$_tmp"
  cat "$_tmp" > "$HOSTNAME_REGISTRY"
  rm -f "$_tmp"
}

_hn_apply() {      # name -- the only part that touches the machine
  local _short="$1"
  local _pretty="${HOST_PRETTY:-$(printf '%s' "${_short:0:1}" \
                  | tr '[:lower:]' '[:upper:]')${_short:1}}"
  local _netbios="${HOST_NETBIOS:-$(printf '%s' "$_short" | tr '[:lower:]' '[:upper:]')}"

  sudo scutil --set ComputerName  "$_pretty" && ok "ComputerName  = $_pretty"
  sudo scutil --set LocalHostName "$_short"  && ok "LocalHostName = $_short  (-> $_short.local)"
  # Bare name, no domain: this machine moves between networks, so a hardcoded
  # search domain would lie.
  sudo scutil --set HostName      "$_short"  && ok "HostName      = $_short"
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server \
    NetBIOSName -string "$_netbios" >/dev/null 2>&1 \
    && ok "NetBIOSName   = $_netbios"
  dscacheutil -flushcache 2>/dev/null || true
  ok "renamed — new terminals will show the new prompt"
}

# ── Decide ────────────────────────────────────────────────────
_hn_current="$(scutil --get LocalHostName 2>/dev/null || true)"

if ! _hn_id="$(machine_id)" || [[ -z "$_hn_id" ]]; then
  # Fail closed. Without an identity this step cannot tell "my own name" from
  # "someone else's", and guessing wrong is how two machines collide.
  warn "could not read this machine's hardware serial — not touching the name"
  warn "    every branch below needs a machine identity to be safe"
elif [[ -z "${HOST_SHORT:-}" ]]; then
  # No name asked for. Never rename; adopt the current one if it is deliberate
  # and free, so an already-named machine gets recorded without being touched.
  _hn_holder="$(_hn_claimant "$_hn_current")"
  if [[ -n "$_hn_holder" && "$_hn_holder" == "$_hn_id" ]]; then
    ok "host name '$_hn_current' is registered to this machine"
  elif [[ -n "$_hn_holder" ]]; then
    warn "this machine answers to '$_hn_current', but the registry gives that"
    warn "    name to machine $_hn_holder. One of them has to change:"
    warn "    HOST_SHORT=<name> ./setup.sh"
  elif name_leaks_serial "$_hn_current"; then
    warn "HOST_SHORT not set — leaving this machine as '$_hn_current'"
    warn "    That name contains this machine's hardware serial, which is how"
    warn "    an MDM names things. It is NOT recorded: the registry is tracked"
    warn "    and mirrored, and the machine-id is hashed precisely so the"
    warn "    serial stays out of it."
    warn "    Give it a name of your own:  HOST_SHORT=<name> ./setup.sh"
  elif _hn_is_factory_name "$_hn_current"; then
    warn "HOST_SHORT not set — leaving this machine as '$_hn_current'"
    warn "    that looks like a factory name, so it is not recorded either."
    warn "    Name it deliberately:  HOST_SHORT=<name> ./setup.sh"
  else
    _hn_claim "$_hn_current" "$_hn_id"
    ok "recorded '$_hn_current' as this machine's name (nothing renamed)"
    warn "    commit $(basename "$HOSTNAME_REGISTRY"), or the next machine can take it"
  fi
else
  _hn_holder="$(_hn_claimant "$HOST_SHORT")"
  if name_leaks_serial "$HOST_SHORT"; then
    err "'$HOST_SHORT' contains this machine's hardware serial — refusing."
    err "    Claiming it would write the serial into $(basename "$HOSTNAME_REGISTRY"),"
    err "    which is tracked and mirrored. The machine-id is hashed for that"
    err "    exact reason; a name carrying the serial puts it straight back."
  elif [[ -n "$_hn_holder" && "$_hn_holder" != "$_hn_id" ]]; then
    # The whole point of the registry: this catches a name held by a machine
    # that is switched off, elsewhere, or long retired, which no network probe
    # can ever see.
    err "'$HOST_SHORT' is already claimed by machine $_hn_holder"
    err "    (this machine is $_hn_id). Pick another name, or -- if that"
    err "    machine is retired -- delete its line from"
    err "    $HOSTNAME_REGISTRY and commit."
  elif [[ "$_hn_current" == "$HOST_SHORT" && -n "$_hn_holder" ]]; then
    ok "host name is already '$HOST_SHORT', and registered to this machine"
  else
    _hn_previous="$(_hn_name_of "$_hn_id")"
    [[ -n "$_hn_previous" && "$_hn_previous" != "$HOST_SHORT" ]] \
      && log "this machine was registered as '$_hn_previous' — releasing that name"
    log "current: ComputerName='$(scutil --get ComputerName 2>/dev/null || true)' LocalHostName='$_hn_current'"
    _hn_apply "$HOST_SHORT"
    _hn_claim "$HOST_SHORT" "$_hn_id"
    ok "claimed '$HOST_SHORT' for this machine"
    warn "    commit $(basename "$HOSTNAME_REGISTRY"), or the next machine can take it"
  fi
fi

unset _hn_current _hn_id _hn_holder _hn_previous
