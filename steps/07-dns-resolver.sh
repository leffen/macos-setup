# steps/07-dns-resolver.sh — pin internal DNS zones to their own servers
#
# A VPN client that sets a global DNS server (WireGuard's `DNS =` line, which
# macOS applies system-wide) takes down ALL name resolution the moment the
# tunnel stops forwarding -- public lookups included, because they are sent to
# a resolver that only exists on the far side. That failure mode reads as
# "nothing works at all" and is indistinguishable from the network being down.
#
# Files under /etc/resolver avoid it entirely: each pins ONE zone to ONE
# server, leaves public DNS on the Wi-Fi nameservers, is static across
# reconnects, and cannot break anything outside its own zone. Prefer this over
# a global DNS line in the tunnel config.
#
# Only zones that do not resolve publicly need an entry. Check first:
#   dig @8.8.8.8 host.example.lan +short     # empty  -> needs a resolver file
#                                            # answer -> needs nothing, just a route
# A domain that publishes its internal addresses in public DNS needs no
# entry here -- only a route through the tunnel.
#
# Format is space-separated zone=server pairs, so several sites can coexist:
#   INTERNAL_ZONES="home.lan=192.168.1.1 other.lan=10.0.0.1" ./setup.sh

# Back-compat: honour the old single-zone variables if they are set.
if [[ -n "${INTERNAL_ZONE:-}" ]]; then
  INTERNAL_ZONES="${INTERNAL_ZONE}=${INTERNAL_DNS:?set INTERNAL_DNS with INTERNAL_ZONE}"
fi
INTERNAL_ZONES="${INTERNAL_ZONES:-}"
if [[ -z "$INTERNAL_ZONES" ]]; then
  ok "no INTERNAL_ZONES set; no split-DNS resolver files needed"
  return 0
fi

# Split explicitly rather than relying on unquoted word splitting, which does
# not happen under zsh and would collapse every pair into one.
read -ra _zone_pairs <<<"$INTERNAL_ZONES"

for pair in "${_zone_pairs[@]}"; do
  zone="${pair%%=*}"
  server="${pair#*=}"
  resolver_file="/etc/resolver/$zone"

  log "Pinning .$zone lookups to $server..."

  if [[ -f "$resolver_file" ]] && grep -qx "nameserver $server" "$resolver_file" 2>/dev/null; then
    ok "$resolver_file already correct"
  else
    sudo mkdir -p /etc/resolver
    printf 'nameserver %s\n' "$server" | sudo tee "$resolver_file" >/dev/null
    ok "wrote $resolver_file"
  fi

  # Confirm through the macOS resolver stack. dig/host/nslookup are useless
  # here: they query nameservers directly and bypass /etc/resolver entirely,
  # reporting failure even when resolution works.
  #
  # Bounded, because an unanswered query to a server that is only reachable
  # through the tunnel blocks for tens of seconds when the tunnel is down.
  probe=$(mktemp)
  dscacheutil -q host -a name "unifi.$zone" >"$probe" 2>/dev/null &
  probe_pid=$!
  waited=0
  while kill -0 "$probe_pid" 2>/dev/null && (( waited < 50 )); do
    sleep 0.1; waited=$((waited + 1))
  done
  kill -9 "$probe_pid" 2>/dev/null || true
  wait "$probe_pid" 2>/dev/null || true

  if grep -q '^ip_address:' "$probe"; then
    ok "unifi.$zone resolves"
  else
    warn "unifi.$zone does not resolve — expected unless the VPN is connected"
  fi
  rm -f "$probe"
done
