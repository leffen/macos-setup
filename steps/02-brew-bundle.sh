# steps/02-brew-bundle.sh — install everything from the Brewfile

ensure_brew

# Kept so the output can be both watched live AND read back afterwards: the
# diagnosis below depends on what brew actually said.
_bb_log="$(mktemp -t brew-bundle)"

log "Installing packages from Brewfile (this can take a while)..."

# `set -o pipefail` (lib/common.sh) is what makes this `if` test brew's exit
# status rather than tee's. Without it the pipeline always reports tee's 0 and
# every failure in here looks like a clean run -- a trap worth naming, because
# it is easy to add a `| tee` to a working check and silently disarm it.
if brew bundle --file="$REPO_ROOT/Brewfile" 2>&1 | tee "$_bb_log"; then
  ok "Brew packages installed"
else
  # WHY it failed matters more than that it did: brew reports every cause as
  # the same "has failed!" line, and each one wants a different answer.

  # 1. The network went away mid-run. This is the 13 Sep failure: DNS was fine
  #    at preflight and died during the downloads. Every later step downloads
  #    too, so continuing only buys more noise -- and, worse, a later step
  #    reporting a missing tool as though the Brewfile were at fault.
  #
  #    Ending the run from a sourced step is the exception to this repo's "a
  #    step never exits" rule. It is deliberate: there is nothing useful left
  #    to do, and the alternative is the cascade this guard exists to stop.
  if ! net_ok ghcr.io; then
    err "the network went away DURING brew bundle."
    err "    Nothing above is a real package failure -- they are all"
    err "    'Could not resolve host'. The run stops here rather than"
    err "    cascading through the steps that download too."
    err "    On Cloudflare WARP, start with:  warp-cli status"
    err "    Then re-run:  make setup"
    rm -f "$_bb_log"
    exit 1
  fi

  # 2. Whatever brew actually said, reported ahead of the specific cases below
  #    because of a pattern that showed up twice on 13 Sep: `brew bundle` plans
  #    the whole batch before installing any of it, so ONE planning error (a
  #    circular dependency, a formula claimed by two taps) aborts everything
  #    and prints "has failed!" for all ~50 packages. The single line that
  #    explains it scrolls past long before the noise ends, and every
  #    "has failed!" line is innocent.
  _bb_errors="$(grep -E '^Error:' "$_bb_log" | sort -u || true)"
  if [[ -n "$_bb_errors" ]]; then
    warn "brew reported these errors -- read these, not the 'has failed!' lines:"
    while IFS= read -r _bb_e; do
      [[ -n "$_bb_e" ]] && warn "    $_bb_e"
    done <<< "$_bb_errors"
    warn "    One error here fails the ENTIRE bundle: the batch is planned"
    warn "    before anything installs, so the rest is collateral."
  fi

  # 3. Homebrew 7 refuses formulae from taps that are not trusted, and says so
  #    once per macOS version per formula -- dozens of near-identical lines
  #    that scroll the actual instruction away. It also takes TWO commands:
  #    trusting a tap does not tap it, so `brew bundle` still fails afterwards
  #    with "No available formula", which reads like a different problem.
  _bb_untrusted="$(grep -oE 'untrusted tap [^ .]+' "$_bb_log" \
                   | awk '{print $3}' | sort -u || true)"
  if [[ -n "$_bb_untrusted" ]]; then
    warn "Homebrew refused these taps as untrusted, and will on every run:"
    while IFS= read -r _bb_tap; do
      [[ -n "$_bb_tap" ]] || continue
      warn "    brew trust $_bb_tap && brew tap $_bb_tap"
    done <<< "$_bb_untrusted"
    warn "    Trusting a tap lets it run its own code at install time, so this"
    warn "    is left to you rather than done here. Both commands are needed."
  fi

  # 4. A circular dependency in the installed keg tabs. This one reads like a
  #    warning and behaves like a fatal error: the graph sort runs ONCE for the
  #    whole bundle, so when it aborts, every remaining package reports
  #    "has failed!" at the same instant and none of them is the real problem.
  #    On 13 Sep this sat underneath a DNS outage and looked like noise; with
  #    the network healthy it turned out to be what was failing all 53.
  _bb_circular="$(grep -A1 'circular dependency' "$_bb_log" \
                  | grep -vE 'circular dependency|^--' | tr -d ' ' | sort -u || true)"
  if [[ -n "$_bb_circular" ]]; then
    warn "a circular dependency aborted the dependency sort, which fails the"
    warn "    ENTIRE bundle at once -- the 'has failed!' lines above are all"
    warn "    collateral, not real package failures. Clear the stale keg tabs:"
    while IFS= read -r _bb_pkgs; do
      [[ -n "$_bb_pkgs" ]] || continue
      _bb_pkgs="${_bb_pkgs//,/ }"
      warn "    brew uninstall --ignore-dependencies --force $_bb_pkgs"
      warn "    brew install $_bb_pkgs"
    done <<< "$_bb_circular"
    warn "    Then re-run:  make setup"
  fi

  warn "Some Brewfile entries failed — review the output above and re-run if needed"
fi

rm -f "$_bb_log"
unset _bb_log _bb_untrusted _bb_tap _bb_circular _bb_pkgs _bb_errors _bb_e
