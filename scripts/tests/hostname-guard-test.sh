#!/bin/bash
# scripts/tests/hostname-guard-test.sh — does the serial guard actually catch
# the name an MDM produces?
#
# WHY THIS EXISTS
#
# The first version of name_leaks_serial asked whether a name contained the
# WHOLE serial. It read correctly, it was committed as a fix, and it did not
# work: Intune names this machine corpmac-<serial minus its first character>, so
# 9 of 10 characters were present, the check passed, and the name was treated
# as ordinary. The guard could then have written most of the serial into the
# mirrored hostnames registry and into a signing-key comment published to two
# forges.
#
# Nothing about that was visible by reading the function. It needed a case.
# Case 2 below is that exact shape, and it is the reason this file exists.
#
# The serial used here is fabricated. The real one is never written down --
# that is the whole point of the code under test -- and MACHINE_SERIAL is the
# override the steps already provide so this runs without a second Mac.
#
# Usage:  make test     (or: bash scripts/tests/hostname-guard-test.sh)
#
# Exit status: 0 all cases pass, 1 a case failed.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO/lib/common.sh" || exit 2

# common.sh sets -euo pipefail. A failing assertion must be REPORTED, not abort
# the run before the remaining cases get a chance to say anything.
set +eu

SERIAL="C02ZZ9TESTAB"   # fabricated, 12 chars, same shape as an Apple serial
FAILED=0
RAN=0

# check <description> <leak|clean> <serial> <name>
check() {
  local desc="$1" expect="$2" serial="$3" name="$4" got
  RAN=$((RAN + 1))
  if MACHINE_SERIAL="$serial" name_leaks_serial "$name"; then got=leak; else got=clean; fi
  if [ "$got" = "$expect" ]; then
    printf '  ok    %s\n' "$desc"
  else
    printf '  FAIL  %s — expected %s, got %s\n' "$desc" "$expect" "$got"
    FAILED=$((FAILED + 1))
  fi
}

echo "name_leaks_serial (SERIAL_MIN_RUN=${SERIAL_MIN_RUN:-8})"

check "whole serial in the name"            leak  "$SERIAL" "corpmac-c02zz9testab"
check "MDM shape: first character dropped"  leak  "$SERIAL" "corpmac-02zz9testab"
check "uppercase name, lowercase serial"    leak  "$SERIAL" "CORPMAC-C02ZZ9TESTAB"
check "serial with a character trimmed off" leak  "$SERIAL" "corpmac-c02zz9testa"
check "exactly the 8-character threshold"   leak  "$SERIAL" "host-c02zz9te"
check "one short of the threshold"          clean "$SERIAL" "host-c02zz9t"
check "a chosen name"                       clean "$SERIAL" "nami"
check "another chosen name"                 clean "$SERIAL" "kaito"
check "a factory name"                      clean "$SERIAL" "macbook-pro"
check "empty name"                          clean "$SERIAL" ""

# A serial shorter than the threshold must be compared whole rather than
# skipped -- "too short to check" would be a silent hole.
check "short serial, present in the name"   leak  "ABC"     "host-abc-1"
check "short serial, absent from the name"  clean "ABC"     "nami"

# No serial at all is "no evidence", never "proven safe". The callers treat a
# false return as unknown and refuse to record, which is tested by the step,
# not here; what matters here is that it does not crash or claim a leak.
check "empty serial cannot be compared"     clean ""        "corpmac-c02zz9testab"

echo
if [ "$FAILED" -eq 0 ]; then
  printf '%s cases, all passed\n' "$RAN"
  exit 0
fi
printf '%s of %s cases FAILED\n' "$FAILED" "$RAN"
exit 1
