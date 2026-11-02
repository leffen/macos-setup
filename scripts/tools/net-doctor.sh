#!/bin/bash
# scripts/tools/net-doctor.sh — say what is actually wrong with this machine's
# network, including when Microsoft Defender is the thing breaking it.
#
# WHY THIS EXISTS
#
# Four different faults on this machine look identical from the prompt: some
# hosts hang or refuse, TLS fails on the issuer, internal names resolve wrong,
# and long-lived connections never return a first byte. Claude Code hanging
# forever at startup is the recurring case.
#
# The checks below cover Defender too, the one component whose failure is
# invisible to most other network tools.
#
# Defender's network extension (com.microsoft.wdav.netext) is a content filter.
# It intercepts flows ABOVE the socket layer, so a connection it blocks will
# resolve, connect, and finish its TLS handshake before stalling. Every layer-3
# probe reports success. ping and dig agree the host is fine while curl hangs.
#
# So this script times DNS, connect, TLS and first byte SEPARATELY. The gap
# between them is the diagnosis:
#
#   connect fast, TLS fast, first byte never  ->  content filter (Defender)
#   connect fast, TLS fails on issuer         ->  interception / proxy MITM
#   connect times out                         ->  routing, or an upstream block
#   DNS slow or wrong                         ->  resolver or split-horizon
#   all four slow together                    ->  the link itself
#
# WHAT IT DOES NOT DO
#
# It changes nothing: no routes, no resolvers, no firewall rules, and no
# Defender settings. Defender here is managed by policy (tamper_protection is
# "block" and the settings read [managed]); disabling it is neither possible
# nor appropriate. The output is shaped to be evidence you can hand to IT.
#
# The default run needs no sudo. Anything it cannot read without privilege is
# reported as unknown rather than guessed at or escalated.
#
# Usage:
#   ./scripts/tools/net-doctor.sh                 # full passive sweep, ~15s
#   ./scripts/tools/net-doctor.sh --quick         # skip slow probes, ~3s
#   ./scripts/tools/net-doctor.sh --trace         # prove a Defender block
#   ./scripts/tools/net-doctor.sh --baseline      # record known-good state
#   ./scripts/tools/net-doctor.sh --diff          # this run vs the baseline
#   ./scripts/tools/net-doctor.sh --host example.com --host other.internal
#
# Exit status: 0 nothing wrong, 1 findings raised, 2 the script could not run.
#
# Deliberately does NOT source lib/common.sh -- `set -euo pipefail` would abort
# the run the first time a probe legitimately fails, and failing probes are the
# entire signal this script exists to collect.

# No `set -e`: see above. No `set -u` either -- the default bash on macOS is
# 3.2, where expanding an empty array under `set -u` is itself an error.
set -o pipefail 2>/dev/null || true

VERSION="1.0"

# ---------------------------------------------------------------- presentation

if [ -t 1 ] && [ -z "${NO_COLOR}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[1;31m'; C_YEL=$'\033[1;33m'; C_GRN=$'\033[1;32m'; C_BLU=$'\033[1;34m'
  C_DIM=$'\033[2m'
else
  C_RESET=; C_BOLD=; C_RED=; C_YEL=; C_GRN=; C_BLU=; C_DIM=
fi

# Evidence is buffered so the ranked verdict can be printed above it.
EV="$(mktemp -t net-doctor-ev)"
FIND="$(mktemp -t net-doctor-find)"
TRACE_STARTED=0

cleanup() {
  [ "$TRACE_STARTED" = "1" ] && mdatp network-protection trace stop >/dev/null 2>&1
  rm -f "$EV" "$FIND"
}
trap cleanup EXIT INT TERM

ev()      { printf '%s\n' "$*" >> "$EV"; }
ev_head() { printf '\n%s%s%s\n' "$C_BLU" "$*" "$C_RESET" >> "$EV"; }

# finding <severity 3|2|1> <title> <evidence>
#   3 FAIL  something is broken
#   2 WARN  suspicious, explains a symptom
#   1 INFO  worth knowing, not itself a fault
finding() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FIND"; }

status_line() {
  # status_line OK|WARN|FAIL <text>
  case "$1" in
    OK)   printf '  %s%s%s %s\n' "$C_GRN" "OK  " "$C_RESET" "$2" >> "$EV" ;;
    WARN) printf '  %s%s%s %s\n' "$C_YEL" "WARN" "$C_RESET" "$2" >> "$EV" ;;
    FAIL) printf '  %s%s%s %s\n' "$C_RED" "FAIL" "$C_RESET" "$2" >> "$EV" ;;
    *)    printf '  %s%s%s %s\n' "$C_DIM" "----" "$C_RESET" "$2" >> "$EV" ;;
  esac
}

# Baseline lives next to the other per-machine state this repo writes to $HOME.
BASELINE="${HOME}/.net-doctor-baseline"
BASE_OUT="$(mktemp -t net-doctor-base)"
base_record() { printf '%s=%s\n' "$1" "$2" >> "$BASE_OUT"; }

# ---------------------------------------------------------------- arguments

MODE="sweep"
QUICK=0
HOSTS=""

usage() {
  sed -n '2,58p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)    QUICK=1 ;;
    --trace)    MODE="trace" ;;
    --baseline) MODE="baseline" ;;
    --diff)     MODE="diff" ;;
    --host)     shift; [ -z "$1" ] && { echo "--host needs a value" >&2; exit 2; }
                HOSTS="$HOSTS $1" ;;
    -h|--help)  usage 0 ;;
    *)          echo "unknown option: $1" >&2; usage 2 ;;
  esac
  shift
done

# api.anthropic.com first: it is the endpoint behind the hang that prompted
# this script. The internal name proves split-horizon DNS still works.
ENDPOINTS="api.anthropic.com github.com registry.npmjs.org"
INTERNAL_HOST="${INTERNAL_HOST:-}"   # e.g. INTERNAL_HOST=router.home.lan, to check split DNS
[ -n "$HOSTS" ] && ENDPOINTS="$ENDPOINTS $HOSTS"

need() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 1. link

stage_link() {
  ev_head "1. Link and egress"

  local dflt iface gw dflt6
  dflt="$(route -n get default 2>/dev/null)"
  iface="$(printf '%s' "$dflt" | awk '/interface:/{print $2}')"
  gw="$(printf '%s' "$dflt" | awk '/gateway:/{print $2}')"
  dflt6="$(route -n get -inet6 default 2>/dev/null | awk '/interface:/{print $2}')"

  if [ -z "$iface" ]; then
    status_line FAIL "no IPv4 default route -- this machine has no egress at all"
    finding 3 "No default route" "route -n get default returned no interface. Nothing will reach the network until this is fixed."
    return
  fi

  status_line OK "default route via ${iface}${gw:+ -> $gw}"
  base_record iface "$iface"
  base_record gateway "$gw"

  case "$iface" in
    utun*)
      status_line INFO "full-tunnel VPN carries the default route (${iface})"
      finding 1 "Full-tunnel VPN is active" "Default route is on ${iface}. All traffic egresses through the tunnel, so an upstream block is the site's, not this machine's."
      ;;
  esac

  # macOS races IPv6 and IPv4 (Happy Eyeballs) and prefers IPv6. If the two
  # default routes leave by different interfaces, dual-stack hosts are reached
  # over one path while every IPv4 probe measures the other -- which is why
  # this rates a finding rather than a passing remark.
  if [ -n "$dflt6" ] && [ "$dflt6" != "$iface" ]; then
    status_line WARN "IPv6 default route is on ${dflt6}, IPv4 on ${iface} -- split egress"
    finding 2 "IPv4 and IPv6 leave by different interfaces" \
      "IPv6 egresses via ${dflt6} while IPv4 egresses via ${iface}. macOS prefers IPv6, so a dual-stack host is reached through ${dflt6} even though every IPv4 test here measures ${iface}. If ${dflt6} half-works, connections hang instead of failing and the IPv4 probes keep reporting success. Test it with: curl -6 -sS --max-time 10 -o /dev/null -w '%{http_code}\\n' https://api.anthropic.com/  against  curl -4 (same flags)."
  fi

  if [ -n "$gw" ]; then
    if ping -c 1 -W 2000 "$gw" >/dev/null 2>&1; then
      status_line OK "gateway $gw answers"
    else
      # Plenty of gateways drop ICMP on purpose, so this is never a FAIL.
      status_line WARN "gateway $gw does not answer ping (may be filtered by policy)"
    fi
  fi

  local ssid
  ssid="$(ipconfig getsummary "$iface" 2>/dev/null | awk -F' SSID : ' '/ SSID : /{print $2; exit}')"
  [ -n "$ssid" ] && { status_line INFO "Wi-Fi network: $ssid"; base_record ssid "$ssid"; }
}

# ---------------------------------------------------------------- 2. DNS

stage_dns() {
  ev_head "2. DNS"

  local ns
  ns="$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3; exit}')"
  if [ -z "$ns" ]; then
    status_line FAIL "no resolver configured"
    finding 3 "No DNS resolver" "scutil --dns lists no nameserver. Every name lookup will fail."
  else
    status_line OK "system resolver: $ns"
    base_record resolver "$ns"
  fi

  # A VPN that does not push a resolver leaves the venue's one in place,
  # so queries for internal names leak out through it.
  local scoped
  scoped="$(scutil --dns 2>/dev/null | grep -c 'nameserver\[')"
  status_line INFO "$scoped resolver entries across all scopes"

  local ext
  ext="$(dig +short +time=3 +tries=1 github.com 2>/dev/null | head -1)"
  if [ -n "$ext" ]; then
    status_line OK "external name resolves (github.com -> $ext)"
  else
    status_line FAIL "external name does not resolve (github.com)"
    finding 3 "External DNS is not resolving" "dig github.com returned nothing via resolver ${ns:-none}. Everything that is not an IP literal will fail."
  fi

  if [ -z "$INTERNAL_HOST" ]; then
    status_line INFO "no INTERNAL_HOST set; split-horizon DNS not checked"
    return
  fi
  local int
  int="$(dig +short +time=3 +tries=1 "$INTERNAL_HOST" 2>/dev/null | head -1)"
  if [ -n "$int" ]; then
    status_line OK "internal name resolves ($INTERNAL_HOST -> $int)"
  else
    status_line WARN "internal name does not resolve ($INTERNAL_HOST)"
    finding 2 "Split-horizon DNS is not working" "$INTERNAL_HOST did not resolve via ${ns:-the current resolver}. Internal hosts will be unreachable by name."
  fi
}

# ---------------------------------------------------------------- 3. layers

# The heart of the script. Four timings per endpoint; the shape of the gaps
# names the fault. See the header comment.
probe_endpoint() {
  local host="$1" out code t_dns t_con t_tls t_first
  out="$(curl -sS -o /dev/null --max-time "${CURL_MAX:-12}" \
          -w '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}' \
          "https://${host}/" 2>/dev/null)"
  local rc=$?
  if [ $rc -ne 0 ]; then
    set -- $out
    t_con="${3:-0}"; t_tls="${4:-0}"
    # curl 28 is timeout. Connected and negotiated TLS but never got a byte is
    # the content-filter signature -- that distinction is the whole point.
    if [ "$rc" = "28" ] && [ "${t_tls%%.*}" -ge 0 ] && \
       awk "BEGIN{exit !(${t_tls:-0} > 0)}"; then
      status_line FAIL "$host: TLS completed in ${t_tls}s then no first byte before timeout"
      finding 3 "$host stalls after a successful TLS handshake" \
        "connect=${t_con}s tls=${t_tls}s then nothing until the ${CURL_MAX:-12}s timeout. A stall AFTER the handshake is what a content filter looks like -- Defender's network extension is the first suspect, not routing."
    elif [ "$rc" = "28" ]; then
      status_line FAIL "$host: timed out before TLS (connect=${t_con}s)"
      finding 3 "$host times out at the network layer" \
        "curl timed out with connect=${t_con}s and no TLS. That is routing, an upstream firewall, or the host being down -- not a content filter."
    elif [ "$rc" = "35" ] || [ "$rc" = "60" ]; then
      status_line FAIL "$host: TLS handshake failed (curl $rc)"
      finding 3 "$host fails TLS verification" \
        "curl exited $rc. Either the chain is being rewritten by an intercepting proxy, or the trust store is missing an issuer. Stage 4 shows who actually signed it."
    elif [ "$rc" = "6" ]; then
      status_line FAIL "$host: could not resolve"
      finding 3 "$host does not resolve" "curl exited 6. A DNS problem, not a connectivity one -- see stage 2."
    else
      status_line FAIL "$host: curl exited $rc"
      finding 2 "$host is unreachable (curl $rc)" "curl exited $rc against https://${host}/."
    fi
    return
  fi

  set -- $out
  code="$1"; t_dns="$2"; t_con="$3"; t_tls="$4"; t_first="$5"
  status_line OK "$host: http=$code dns=${t_dns}s connect=${t_con}s tls=${t_tls}s first-byte=${t_first}s"
  base_record "reach_$host" "$code"

  # Connected and handshook quickly but the first byte took most of the time:
  # the filter let it through but inspected it.
  awk "BEGIN{exit !(${t_first} - ${t_tls} > 3.0)}" && {
    status_line WARN "$host: ${t_first}s to first byte after a ${t_tls}s handshake"
    finding 2 "$host is slow only after the handshake" \
      "TLS finished at ${t_tls}s but the first byte arrived at ${t_first}s. Delay concentrated after the handshake points at inspection, not at the link."
  }
}

stage_reach() {
  ev_head "3. Reachability, timed by layer"
  local h
  for h in $ENDPOINTS; do probe_endpoint "$h"; done
}

# ---------------------------------------------------------------- 4. TLS

stage_tls() {
  ev_head "4. TLS integrity"
  local h issuer
  for h in $ENDPOINTS; do
    issuer="$(echo | timeout 10 openssl s_client -connect "${h}:443" -servername "$h" 2>/dev/null \
              | awk -F'issuer=' '/^issuer=/{print $2; exit}')"
    if [ -z "$issuer" ]; then
      status_line WARN "$h: could not read the served certificate"
      continue
    fi
    base_record "issuer_$h" "$issuer"
    # A public CA is expected. Anything naming Microsoft, Defender or the
    # company is interception, which explains every issuer error you hit.
    case "$issuer" in
      *Microsoft*|*Defender*|*Zscaler*|*Netskope*|*Proxy*|*Firewall*)
        status_line FAIL "$h: served by ${issuer}"
        finding 3 "TLS to $h is being intercepted" \
          "The certificate is issued by ${issuer}, not a public CA. Tools with their own trust store (git, npm, python, Claude Code) will reject it even when the browser accepts it."
        ;;
      *)
        status_line OK "$h: issuer ${issuer}"
        ;;
    esac
  done
}

# ---------------------------------------------------------------- 5. Defender

stage_defender() {
  ev_head "5. Microsoft Defender posture"

  if ! need mdatp; then
    status_line INFO "mdatp is not installed -- Defender is not the cause here"
    return
  fi

  local health rtp npstatus nplevel healthy
  health="$(mdatp health 2>/dev/null)"
  if [ -z "$health" ]; then
    status_line WARN "mdatp is installed but did not answer"
    finding 2 "Defender is installed but not responding" "mdatp health returned nothing. The daemon may be wedged, which is itself a cause of stalled connections."
    return
  fi

  hv() { printf '%s' "$health" | awk -F': ' -v k="$1" '$0 ~ "^"k" *:" {gsub(/^ +| +$|"/,"",$2); print $2; exit}'; }

  healthy="$(hv healthy)"
  rtp="$(hv real_time_protection_enabled)"
  npstatus="$(hv network_protection_status)"
  nplevel="$(hv network_protection_enforcement_level)"

  [ "$healthy" = "true" ] && status_line OK "mdatp reports healthy" \
                          || { status_line WARN "mdatp reports healthy=$healthy"
                               finding 2 "Defender reports itself unhealthy" "mdatp health says healthy=$healthy. An unhealthy agent can fail flows closed."; }

  status_line INFO "real-time protection: $rtp"
  status_line INFO "network protection: ${npstatus:-unknown}, enforcement: ${nplevel:-unknown}"
  base_record np_status "$npstatus"
  base_record np_level "$nplevel"

  # This is the setting that can silently kill a connection. Record it loudly
  # whenever it is enforcing, because it reframes every other symptom above.
  case "$nplevel" in
    *block*)
      status_line INFO "network protection is ENFORCING (block)"
      finding 1 "Defender network protection is in block mode" \
        "network_protection_enforcement_level=${nplevel}. Flows it decides against are dropped above the socket layer, which looks exactly like a hang. Run --trace while reproducing to confirm or clear it. This setting is managed by policy: do not try to change it, take the trace to IT."
      ;;
    *audit*)
      status_line OK "network protection is in audit mode -- it logs but does not block"
      ;;
  esac

  local ext
  ext="$(systemextensionsctl list 2>/dev/null | grep -c 'com.microsoft.wdav.*activated enabled')"
  status_line INFO "$ext Defender system extension(s) activated and enabled"

  local excl
  excl="$(mdatp network-protection exclusion list 2>/dev/null | grep -v '^=*$' | grep -v 'No exclusions')"
  if [ -n "$excl" ]; then
    status_line INFO "network protection exclusions are configured:"
    printf '%s\n' "$excl" | sed 's/^/        /' >> "$EV"
  else
    status_line INFO "no network protection exclusions configured"
  fi
}

# ---------------------------------------------------------------- 6. local

stage_local() {
  ev_head "6. Local blockers"

  local fw
  fw="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
  case "$fw" in
    *"State = 1"*|*"State = 2"*) status_line OK "application firewall is on (inbound only -- does not affect outbound)" ;;
    *"State = 0"*)               status_line INFO "application firewall is off" ;;
    *)                           status_line INFO "application firewall state unknown" ;;
  esac

  # harden-roaming.sh can leave pf rules in place. Reading them needs root,
  # and this script does not escalate -- unknown is an honest answer.
  if sudo -n pfctl -s info >/dev/null 2>&1; then
    local pfen
    pfen="$(sudo -n pfctl -s info 2>/dev/null | awk '/Status:/{print $2; exit}')"
    status_line INFO "pf is $pfen"
    if [ "$pfen" = "Enabled" ]; then
      finding 1 "pf is enabled" "harden-roaming.sh may have left rules active. 'sudo ./scripts/tools/harden-roaming.sh status' shows them, and 'off' clears them."
    fi
  else
    status_line INFO "pf state unknown (needs sudo; run 'sudo ./scripts/tools/harden-roaming.sh status')"
  fi

  local p
  for p in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
    eval "local v=\${$p}"
    [ -n "$v" ] && {
      status_line WARN "$p is set to $v"
      finding 2 "A proxy is set in the environment ($p)" \
        "$p=$v. Everything that honours it will go through that proxy, and it will not be obvious from the browser."
    }
  done

  local sysproxy
  sysproxy="$(scutil --proxy 2>/dev/null | grep -cE 'Enable[^=]*: 1')"
  if [ "${sysproxy:-0}" -gt 0 ]; then
    status_line WARN "a system proxy is enabled (scutil --proxy)"
    finding 2 "A system-level proxy is enabled" "scutil --proxy reports an enabled proxy. This applies to apps using the system settings, and explains selective failures."
  else
    status_line OK "no system proxy configured"
  fi

  [ -n "${NO_PROXY}${no_proxy}" ] && status_line INFO "NO_PROXY=${NO_PROXY}${no_proxy}"
}

# ---------------------------------------------------------------- 7. hang

# The reported symptom is Claude Code never finishing startup, which is a POST
# that opens and then waits. A HEAD against the host does not reproduce it.
stage_hang() {
  ev_head "7. Hang signature (the Claude Code startup case)"

  local out rc code t_tls t_first
  out="$(curl -sS -o /dev/null --max-time 20 \
        -X POST -H 'content-type: application/json' -d '{}' \
        -w '%{http_code} %{time_appconnect} %{time_starttransfer}' \
        https://api.anthropic.com/v1/messages 2>/dev/null)"
  rc=$?
  set -- $out
  code="${1:-000}"; t_tls="${2:-0}"; t_first="${3:-0}"

  # No credentials are sent: an unauthenticated POST returns 401 quickly, and
  # 401 proves the whole path works end to end.
  if [ $rc -eq 0 ] && [ "$code" = "401" ]; then
    status_line OK "POST to api.anthropic.com answered 401 in ${t_first}s -- the path works end to end"
  elif [ $rc -eq 28 ]; then
    status_line FAIL "POST to api.anthropic.com never returned (tls=${t_tls}s, timed out at 20s)"
    finding 3 "The Claude API request hangs after connecting" \
      "A POST reached TLS at ${t_tls}s then produced no response in 20s. This is the exact failure behind Claude Code hanging at startup, and a post-handshake stall is the content-filter signature. Re-run with --trace while starting Claude Code."
  elif [ $rc -ne 0 ]; then
    status_line FAIL "POST to api.anthropic.com failed (curl $rc)"
    finding 3 "The Claude API is not reachable (curl $rc)" "A POST to api.anthropic.com exited $rc."
  else
    status_line INFO "POST to api.anthropic.com answered http=$code in ${t_first}s"
  fi
}

# ---------------------------------------------------------------- trace mode

run_trace() {
  if ! need mdatp; then
    echo "mdatp is not installed -- nothing to trace." >&2
    exit 2
  fi

  printf '%s\n' "${C_BOLD}Defender network trace${C_RESET}"
  printf '%s\n' "This starts Defender's own network trace, waits while you reproduce the"
  printf '%s\n' "problem, then stops it and shows what the network extension logged."
  printf '%s\n' "It changes no Defender setting and needs no sudo."
  echo

  local since
  since="$(date '+%Y-%m-%d %H:%M:%S')"

  if mdatp network-protection trace start >/dev/null 2>&1; then
    TRACE_STARTED=1
    printf '%s\n' "  ${C_GRN}trace started${C_RESET} at $since"
  else
    printf '%s\n' "  ${C_YEL}could not start the mdatp trace${C_RESET} -- falling back to the system log only"
  fi

  echo
  printf '%s\n' "${C_BOLD}Reproduce the problem now${C_RESET} (start Claude Code, run the curl that hangs...)"
  printf '%s' "Press Enter when the failure has happened: "
  read -r _

  if [ "$TRACE_STARTED" = "1" ]; then
    mdatp network-protection trace stop >/dev/null 2>&1
    TRACE_STARTED=0
    printf '%s\n' "  ${C_GRN}trace stopped${C_RESET}"
  fi

  echo
  printf '%s\n' "${C_BLU}Defender network-extension events during the window${C_RESET}"
  local events
  # /usr/bin/log, not `log`: see the log rule in the Makefile. A bare `log`
  # here would hit zsh's builtin or lib/common.sh's log() helper, print
  # nothing, and -- with stderr going to /dev/null two lines down -- make this
  # function announce that Defender is innocent on the strength of an empty
  # string. That is the one wrong answer this whole script exists to prevent.
  events="$(/usr/bin/log show --start "$since" \
              --predicate 'subsystem BEGINSWITH "com.microsoft.wdav" OR process CONTAINS "wdav"' \
              --style compact 2>/dev/null \
            | grep -iE 'block|deny|drop|denied|refus' | head -40)"

  if [ -n "$events" ]; then
    printf '%s\n' "$events" | sed 's/^/  /'
    echo
    printf '%s\n' "${C_RED}Defender logged blocking activity during the window.${C_RESET}"
    printf '%s\n' "Network protection is managed by policy on this machine, so the fix is not"
    printf '%s\n' "local: send the lines above, plus the output of a plain run of this script,"
    printf '%s\n' "to whoever administers Defender and ask for the endpoint to be allowed."
  else
    printf '%s\n' "  (no block, deny or drop events logged by Defender in that window)"
    echo
    printf '%s\n' "That is a real result: it clears Defender's network extension for this"
    printf '%s\n' "failure. Run the script without --trace and work down the other findings."
  fi
}

# ---------------------------------------------------------------- verdict

print_verdict() {
  local n_fail n_warn
  n_fail="$(awk -F'\t' '$1==3' "$FIND" | wc -l | tr -d ' ')"
  n_warn="$(awk -F'\t' '$1==2' "$FIND" | wc -l | tr -d ' ')"

  printf '\n%s%s%s\n' "$C_BOLD" "═══ Verdict ═══" "$C_RESET"

  if [ ! -s "$FIND" ]; then
    printf '\n  %sNothing wrong found.%s Every stage passed.\n' "$C_GRN" "$C_RESET"
    printf '  %sIf the problem is intermittent, capture a known-good state now with --baseline,\n' "$C_DIM"
    printf '  then run --diff while it is failing.%s\n' "$C_RESET"
    return 0
  fi

  # Worst first: a FAIL explains the symptom, a WARN colours it.
  local sev title eviden label col
  sort -t"$(printf '\t')" -k1,1nr "$FIND" | while IFS="$(printf '\t')" read -r sev title eviden; do
    case "$sev" in
      3) label="FAIL"; col="$C_RED" ;;
      2) label="WARN"; col="$C_YEL" ;;
      *) label="INFO"; col="$C_DIM" ;;
    esac
    printf '\n  %s%s%s  %s%s%s\n' "$col" "$label" "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
    printf '%s\n' "$eviden" | fold -s -w 74 | sed 's/^/        /'
  done

  echo
  printf '  %s findings: %s failing, %s suspicious%s\n' "$C_DIM" "$n_fail" "$n_warn" "$C_RESET"
  return 0
}

# ---------------------------------------------------------------- main

run_stages() {
  stage_link
  stage_dns
  stage_reach
  [ "$QUICK" = "1" ] || stage_tls
  stage_defender
  stage_local
  [ "$QUICK" = "1" ] || stage_hang
}

case "$MODE" in
  trace)
    run_trace
    exit 0
    ;;

  baseline)
    CURL_MAX=8 run_stages
    sort "$BASE_OUT" > "$BASELINE"
    rm -f "$BASE_OUT"
    printf 'Baseline recorded in %s (%s values).\n' "$BASELINE" "$(wc -l < "$BASELINE" | tr -d ' ')"
    printf 'Run --diff while things are broken to see what moved.\n'
    exit 0
    ;;

  diff)
    if [ ! -f "$BASELINE" ]; then
      echo "No baseline at $BASELINE -- record one with --baseline while things work." >&2
      exit 2
    fi
    CURL_MAX=8 run_stages
    sort "$BASE_OUT" > "${BASE_OUT}.sorted"
    printf '%s%s%s\n' "$C_BOLD" "Changes since the baseline:" "$C_RESET"
    if diff -u "$BASELINE" "${BASE_OUT}.sorted" | grep -E '^[-+][a-z]' | grep -v '^[-+][-+]'; then
      :
    else
      printf '  (nothing changed -- the difference is not in anything this script records)\n'
    fi
    rm -f "$BASE_OUT" "${BASE_OUT}.sorted"
    print_verdict
    exit 0
    ;;
esac

printf '%snet-doctor %s%s  %s\n' "$C_BOLD" "$VERSION" "$C_RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
run_stages
rm -f "$BASE_OUT"

print_verdict

printf '\n%s%s%s\n' "$C_BOLD" "═══ Evidence ═══" "$C_RESET"
cat "$EV"
echo

if awk -F'\t' '$1==3' "$FIND" | grep -q .; then
  printf '%sNext:%s a stalled-after-handshake failure is proved or cleared by:\n' "$C_BOLD" "$C_RESET"
  printf '  ./scripts/tools/net-doctor.sh --trace\n\n'
  exit 1
fi
[ -s "$FIND" ] && exit 1
exit 0
