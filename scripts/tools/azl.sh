#!/usr/bin/env bash
# scripts/tools/azl.sh — `az login` without the noise.
#
# Installed as `azl` on PATH: steps/22-azure-cli.sh symlinks it to
# ~/.local/bin/azl, so edits here are live everywhere.
#
# A bare `az login` prints a JSON array of every subscription the account can
# see, plus browser and tenant warnings on stderr. This keeps the browser flow,
# drops both, and prints one summary line instead. Real errors still show.
#
#   azl                          # browser login, default tenant
#   azl --tenant <tenant-id>     # any other `az login` flag passes through
#   azl --use-device-code        # e.g. over SSH, where no browser can open
#
# If it hangs re-running `brew upgrade azure-cli`, auto-upgrade has been turned
# back on: `az config set auto-upgrade.enable=no` (steps/22 explains why).

set -euo pipefail

command -v az >/dev/null 2>&1 || {
  printf '\033[31merror:\033[0m az not found — brew bundle install --file=Brewfile\n' >&2
  exit 1
}

az login --output none --only-show-errors "$@"

# One line, so it is obvious which subscription later commands will hit.
az account show --only-show-errors \
  --query '[user.name, name, id]' -o tsv |
  {
    IFS=$'\t' read -r user sub id
    printf '\033[32m✓\033[0m %s → %s (%s)\n' "$user" "$sub" "$id"
  }
