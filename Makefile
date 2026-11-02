# Makefile — the things worth running on this repo, and nothing else.
#
#   make            list the targets
#   make verify     is this machine set up correctly?
#   make lint       are the scripts sound?
#
# Nothing here changes the machine except `setup`, `dotfiles`, `keys`,
# `ssh-agent` and `brew-install`, and those say so in their descriptions.
# Everything else is read-only, so it is safe to run any of it to find out
# where you stand.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.SHELLFLAGS := -euo pipefail -c

# Sourced fragments have no shebang on purpose, so shellcheck needs telling
# which dialect they are (SC2148). Standalone scripts carry their own.
FRAGMENTS  := $(wildcard steps/*.sh) lib/common.sh
STANDALONE := setup.sh $(wildcard scripts/tools/*.sh) $(wildcard scripts/tests/*.sh)

# Severity floor for `lint`. See lint-strict.
SEVERITY ?= error

# Run one step the way setup.sh does: sourced, with lib/common.sh already
# loaded. A step alone has no log/ok/warn/link and no DOTFILES_DIR.
STEP = bash -c 'source lib/common.sh && source $(1)'

.PHONY: help setup dotfiles keys ssh-agent brew-install verify lint lint-log lint-strict \
        test secrets-scan tools disk brew

help: ## List these targets
	@printf '\033[1m%s\033[0m\n' "macos-setup"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / \
		{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── changes the machine ───────────────────────────────────────

setup: ## CHANGES THE MACHINE: run every step (safe to re-run)
	./setup.sh

dotfiles: ## CHANGES THE MACHINE: re-link the dotfiles only
	$(call STEP,steps/06-dotfiles.sh)

keys: ## CHANGES THE MACHINE: create/adopt the SSH signing key, write ~/.gitconfig.local
	$(call STEP,steps/18-git-signing-keys.sh)

ssh-agent: ## CHANGES THE MACHINE: store key passphrases in the keychain, rewrite ~/.ssh/agent-keys
	$(call STEP,steps/20-ssh-agent.sh)

brew-install: ## CHANGES THE MACHINE: install everything in the Brewfile
	brew bundle install --file=Brewfile

# ── read-only ─────────────────────────────────────────────────

verify: ## Is this machine set up correctly? (read-only)
	@fail=0; \
	for c in brew git gh kubectl sops go node python3 rustc; do \
		if command -v $$c >/dev/null 2>&1; then printf '  \033[32m✓\033[0m %s\n' "$$c"; \
		else printf '  \033[31m✗\033[0m %s missing\n' "$$c"; fail=1; fi; \
	done; \
	for f in .zshrc .zprofile .zshenv .gitconfig .gitignore; do \
		if [ -L "$$HOME/$$f" ]; then printf '  \033[32m✓\033[0m ~/%s linked\n' "$$f"; \
		else printf '  \033[31m✗\033[0m ~/%s not linked (make dotfiles)\n' "$$f"; fail=1; fi; \
	done; \
	key="$$(git config --get user.signingkey || true)"; key="$${key/#\~/$$HOME}"; \
	email="$$(git config --get user.email || true)"; \
	sig="$$(mktemp)"; trap 'rm -f "$$sig"' EXIT; \
	if [ -n "$$key" ] && [ -f "$$key" ] \
	   && printf 'v' | ssh-keygen -Y sign -f "$${key%.pub}" -n git - > "$$sig" 2>/dev/null \
	   && printf 'v' | ssh-keygen -Y verify -f "$$HOME/.ssh/allowed_signers" -I "$$email" -n git -s "$$sig" >/dev/null 2>&1; then \
		printf '  \033[32m✓\033[0m commit signing works (%s)\n' "$$key"; \
	else \
		printf '  \033[31m✗\033[0m commit signing does not work yet (make keys, then make ssh-agent)\n'; fail=1; \
	fi; \
	exit $$fail

lint: lint-log ## Shellcheck every script (read-only)
	@command -v shellcheck >/dev/null \
		|| { echo "shellcheck missing: brew install shellcheck"; exit 1; }
	shellcheck --severity=$(SEVERITY) $(STANDALONE)
	shellcheck -s bash --severity=$(SEVERITY) $(FRAGMENTS)
	@echo "lint: clean at severity=$(SEVERITY)"

# Two things shadow /usr/bin/log here: zsh's `log` builtin, and lib/common.sh's
# log() helper. Both swallow `log show ...` and print nothing, which reads as
# "the system logged nothing". Shellcheck cannot see it, so this check does.
LOGRULE := (^|[^[:alnum:]_./-])log[[:space:]]+(show|stream|collect|config|erase)[[:space:]]

lint-log: ## Catch bare `log show` -- /usr/bin/log is shadowed twice over
	@if grep -nE '$(LOGRULE)' $(STANDALONE) $(FRAGMENTS); then \
		echo; echo "lint: call /usr/bin/log explicitly on the lines above."; exit 1; \
	fi
	@echo "log: /usr/bin/log everywhere"

lint-strict: ## Shellcheck at warning level -- expect findings
	@$(MAKE) --no-print-directory lint SEVERITY=warning

test: ## Run the unit tests (read-only)
	@for t in scripts/tests/*.sh; do \
		[ -e "$$t" ] || continue; \
		bash "$$t" || exit 1; \
	done

secrets-scan: ## gitleaks over the history (read-only)
	@command -v gitleaks >/dev/null \
		|| { echo "gitleaks missing: brew install gitleaks"; exit 1; }
	gitleaks detect --no-banner --redact

tools: ## Installed vs latest, for the pinned CLIs (read-only)
	./scripts/tools/install-tool.sh --list

disk: ## What disk space is reclaimable? (read-only; --apply to act)
	./scripts/tools/disk-cleanup.sh

brew: ## Is the Brewfile satisfied? (read-only)
	@brew bundle check --file=Brewfile --verbose || true
