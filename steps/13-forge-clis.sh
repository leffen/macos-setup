# steps/13-forge-clis.sh — forge CLI defaults (gh, tea)
#
# The binaries come from the Brewfile; this only sets the defaults that are
# not expressible in a config file. Authentication stays manual and is listed
# in the setup.sh footer — it is interactive and account-specific.

ensure_brew

if command -v gh >/dev/null 2>&1; then
  # ~/.gitconfig already rewrites https://github.com/ to SSH; this makes
  # `gh repo clone` agree with it instead of handing back an HTTPS remote.
  if gh config set git_protocol ssh >/dev/null 2>&1; then
    ok "gh clones over SSH by default"
  else
    warn "could not set gh git_protocol"
  fi
else
  warn "gh not found — skipping (did the Brewfile step run?)"
fi

command -v tea >/dev/null 2>&1 && ok "tea $(tea --version 2>/dev/null | head -n1)" \
  || warn "tea not found — skipping (did the Brewfile step run?)"
