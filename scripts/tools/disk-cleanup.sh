#!/bin/bash
# scripts/tools/disk-cleanup.sh — reclaim disk space without eating data.
#
# WHY THIS EXISTS
#
# On 20 Sep this machine hit 100% full: 127 MB free on a 228 GB volume. That
# is not merely inconvenient, it is a state where things break in ways that
# do not name disk space as the cause. Docker's CLI hung with no error at all
# and stayed hung until space was freed -- twenty minutes went into debugging
# a daemon that was fine. A full disk is a liar.
#
# Finding the space by hand took most of an hour, and three of the findings
# were counter-intuitive enough to be worth encoding rather than rediscovering:
#
#   1. `du` over-reports pnpm projects, badly. pnpm hardlinks node_modules
#      into a shared store, so summing `du` per project counts the same blocks
#      once per project. Twenty-three node_modules that "totalled 13 GB" freed
#      4 GB. This script therefore measures with df before and after, and
#      never quotes a du sum as a reclaim figure.
#
#   2. `docker system df` said "Build Cache: 0B" while 25.9 GB of build cache
#      sat in a buildx builder's state volume. A non-default buildx builder
#      keeps its cache in its own volume, which the daemon reports as a plain
#      local volume, indistinguishable at a glance from a Postgres volume.
#      Hence prune_docker() below, which walks builders explicitly.
#
#   3. The obvious command for #2 -- `docker system prune -a --volumes` --
#      would have destroyed ten project databases (Postgres, Redis, Keycloak)
#      to reclaim 659 MB. It is never run here. See the comment on that
#      function; this is the single most dangerous thing a cleanup script can
#      get wrong.
#
# THE RULE THIS SCRIPT FOLLOWS
#
# Delete only what a command can regenerate: package caches, build output,
# downloaded toolchains, build cache. Never delete what only exists here.
# Anything whose loss would need a re-download AND a decision (a 6 GB model,
# a VM disk, an un-backed-up data directory) is reported, never removed --
# see review() at the bottom. That list is not a TODO for this script to grow
# into; it is deliberately the boundary.
#
# DRY RUN IS THE DEFAULT. Nothing is deleted without --apply.

set -euo pipefail

_self="${BASH_SOURCE[0]:-$0}"
REPO_ROOT="$(cd "$(dirname "$_self")/../.." 2>/dev/null && pwd)"
# shellcheck source=../../lib/common.sh
source "$REPO_ROOT/lib/common.sh"

# ── Options ───────────────────────────────────────────────────
APPLY=0
ASSUME_YES=0
TASK_GROUPS=(caches builds docker)
PROJECT_DIRS=("$HOME/p" "$HOME/go")
PLAYWRIGHT_KEEP=1          # newest build per browser family
OLLAMA_STALE_DAYS=0        # 0 = report only; >0 = remove models older than N days

usage() {
  cat <<'USAGE'
disk-cleanup.sh — reclaim regenerable disk space. Dry run unless --apply.

  --apply               actually delete (default: show what would be deleted)
  --yes                 skip the confirmation prompt under --apply
  --only  a,b,c         run only these groups
  --skip  a,b,c         run all but these groups
  --ollama-stale-days N also remove ollama models unused for N+ days
  --help

GROUPS
  caches   package/browser/tool caches, stale installers   (always safe)
  builds   node_modules + dist/.next/build/.astro          (needs a lockfile)
  docker   buildx builder cache; never touches volumes     (safe, slow rebuild)
  models   ollama models  -- opt-in via --ollama-stale-days

A "review" section always prints at the end: space that needs a human
decision. This script will not delete any of it.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --only) IFS=, read -r -a TASK_GROUPS <<<"$2"; shift 2 ;;
    --skip) IFS=, read -r -a _skip <<<"$2"
            _keep=(); for g in "${TASK_GROUPS[@]}"; do
              for s in "${_skip[@]}"; do [[ "$g" == "$s" ]] && continue 2; done
              _keep+=("$g")
            done; TASK_GROUPS=("${_keep[@]}"); shift 2 ;;
    --ollama-stale-days) OLLAMA_STALE_DAYS="$2"; TASK_GROUPS+=(models); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
done

wants() { local g; for g in "${TASK_GROUPS[@]}"; do [[ "$g" == "$1" ]] && return 0; done; return 1; }

# ── Deletion primitive ────────────────────────────────────────
# Every removal in this script goes through here so that dry-run is structural
# rather than something each function has to remember to honour.
drop() {
  local path="$1" why="${2:-}" size
  [[ -e "$path" ]] || return 0
  size="$(du -sh "$path" 2>/dev/null | cut -f1)"
  if (( APPLY )); then
    if rm -rf -- "$path"; then ok "removed ${size:-?}  ${path/#$HOME/~}${why:+  ($why)}"
    else warn "could not remove ${path/#$HOME/~}"; fi
  else
    log "would remove ${size:-?}  ${path/#$HOME/~}${why:+  ($why)}"
  fi
}

avail_kb() { df -k /System/Volumes/Data | tail -1 | awk '{print $4}'; }

human_kb() { awk -v k="$1" 'BEGIN{ if (k<0) k=-k; printf (k>1048576) ? "%.1f GB" : "%.0f MB", (k>1048576)? k/1048576 : k/1024 }'; }

# ── caches ────────────────────────────────────────────────────
clean_caches() {
  log "caches"

  # Package managers. Each of these re-downloads on next use.
  if command -v brew >/dev/null 2>&1; then
    if (( APPLY )); then brew cleanup --prune=all -q 2>/dev/null || warn "brew cleanup failed"
    else log "would run: brew cleanup --prune=all"; fi
  fi
  if command -v npm >/dev/null 2>&1; then
    if (( APPLY )); then npm cache clean --force >/dev/null 2>&1 || warn "npm cache clean failed"; ok "npm cache cleared"
    else log "would run: npm cache clean --force"; fi
  fi
  if command -v go >/dev/null 2>&1; then
    if (( APPLY )); then go clean -modcache 2>/dev/null || warn "go clean -modcache failed"; ok "go module cache cleared"
    else log "would run: go clean -modcache  ($(du -sh "$HOME/go/pkg/mod" 2>/dev/null | cut -f1 || echo 0))"; fi
  fi
  # pnpm's store is what makes node_modules cheap -- prune unreferenced
  # entries, never delete the store itself.
  if command -v pnpm >/dev/null 2>&1; then
    if (( APPLY )); then pnpm store prune >/dev/null 2>&1 || warn "pnpm store prune failed"; ok "pnpm store pruned"
    else log "would run: pnpm store prune"; fi
  fi

  # Stale Docker Desktop installer payloads.
  drop "$HOME/Library/Application Support/com.docker.install/in_progress" "stale installer"

  # Browser caches ONLY. The profile directories under Application Support
  # hold bookmarks, history and saved passwords and are never touched here.
  drop "$HOME/Library/Caches/Google/Chrome" "browser cache"
  drop "$HOME/Library/Caches/Firefox" "browser cache"
  drop "$HOME/Library/Application Support/Google/GoogleUpdater/crx_cache" "updater cache"

  drop "$HOME/Library/Caches/node-gyp" "rebuildable"
  drop "$HOME/Library/Caches/pip" "rebuildable"

  prune_playwright
}

# Playwright keeps every browser build it has ever downloaded, and nothing
# ever removes the old ones. Keep the newest build per family; a project
# pinned to an older one re-downloads it on next run.
prune_playwright() {
  local root="$HOME/Library/Caches/ms-playwright"
  [[ -d "$root" ]] || return 0
  local families=() d name fam
  while IFS= read -r d; do
    name="$(basename "$d")"
    [[ "$name" == "b" ]] && continue          # playwright's own marker dir
    fam="${name%-*}"
    families+=("$fam")
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d)
  [[ ${#families[@]} -gt 0 ]] || return 0

  for fam in $(printf '%s\n' "${families[@]}" | sort -u); do
    local keep=0
    while IFS= read -r d; do
      if (( keep < PLAYWRIGHT_KEEP )); then keep=$((keep+1)); continue; fi
      drop "$d" "superseded $fam"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -name "$fam-*" \
             -exec stat -f '%m %N' {} \; | sort -rn | cut -d' ' -f2-)
  done
}

# ── builds ────────────────────────────────────────────────────
# A node_modules is only safe to delete if the project can rebuild it exactly.
# No lockfile means reinstalling may resolve different versions, which turns a
# cleanup into a silent dependency bump. Those are skipped and reported.
clean_builds() {
  log "builds"
  local nm parent lock f skipped=0
  while IFS= read -r nm; do
    parent="$(dirname "$nm")"
    [[ -f "$parent/package.json" ]] || { warn "skip (no package.json): ${parent/#$HOME/~}"; skipped=1; continue; }
    lock=""
    for f in pnpm-lock.yaml package-lock.json yarn.lock bun.lockb bun.lock; do
      [[ -f "$parent/$f" ]] && lock="$f" && break
    done
    [[ -n "$lock" ]] || { warn "skip (no lockfile): ${parent/#$HOME/~}"; skipped=1; continue; }
    drop "$nm" "restore: $lock"
  done < <(find "${PROJECT_DIRS[@]}" -type d -name node_modules -prune 2>/dev/null)

  (( skipped )) && warn "skipped dirs above would not reinstall reproducibly -- commit a lockfile first"

  # Build output. .cache and .astro are regenerated by the next build.
  local d
  while IFS= read -r d; do drop "$d" "build output"; done < <(
    find "${PROJECT_DIRS[@]}" -maxdepth 4 -type d \
      \( -name dist -o -name .next -o -name .astro -o -name .cache \) \
      -not -path '*/node_modules/*' -prune 2>/dev/null)
}

# ── docker ────────────────────────────────────────────────────
# Deliberately NOT `docker system prune -a --volumes`. On this machine that
# command would have deleted ten named volumes holding project Postgres,
# Redis and Keycloak data -- irreplaceable -- to reclaim 659 MB. Volumes are
# data. Build cache is not. Only build cache is touched here.
prune_docker() {
  log "docker"
  command -v docker >/dev/null 2>&1 || { warn "docker not installed"; return 0; }
  if ! docker version >/dev/null 2>&1; then
    warn "docker daemon not responding -- skipping (if the disk was full, re-run after the other groups)"
    return 0
  fi

  # The default builder's cache, reported by `docker system df`.
  if (( APPLY )); then
    docker builder prune -af >/dev/null 2>&1 && ok "default build cache pruned" || warn "builder prune failed"
  else
    log "would run: docker builder prune -af"
  fi

  # Named buildx builders each hide their cache in a *_state volume that
  # `docker system df` does not attribute to build cache. This is where the
  # 25.9 GB was.
  # `buildx ls` prints the builder AND its nodes; a node is the builder name
  # plus an index ("gitea-builder" -> "gitea-builder0"). Pruning a node name
  # fails, so keep only names that are not another name + digits.
  local b all
  all="$(docker buildx ls --format '{{.Name}}' 2>/dev/null | sort -u)"
  while IFS= read -r b; do
    [[ -n "$b" && "$b" != "default" && "$b" != "desktop-linux" ]] || continue
    if [[ "$b" =~ ^(.+[^0-9])[0-9]+$ ]] && grep -qxF "${BASH_REMATCH[1]}" <<<"$all"; then
      continue   # this is a node of a builder we already handle
    fi
    if (( APPLY )); then
      docker buildx prune -af --builder "$b" >/dev/null 2>&1 \
        && ok "buildx cache pruned: $b" || warn "buildx prune failed: $b"
    else
      log "would run: docker buildx prune -af --builder $b"
    fi
  done <<<"$all"

  warn "volumes left untouched by design -- inspect with: docker system df -v"
}

# ── models (opt-in) ───────────────────────────────────────────
clean_models() {
  log "ollama models"
  command -v ollama >/dev/null 2>&1 || { warn "ollama not installed"; return 0; }
  if (( OLLAMA_STALE_DAYS <= 0 )); then
    ollama list 2>/dev/null | sed 1d | while read -r name _ size unit rest; do
      log "keeping $name ($size $unit, last modified: $rest) -- pass --ollama-stale-days N to remove"
    done
    return 0
  fi
  # `ollama list` prints relative ages ("11 months ago"); months and years are
  # the only buckets coarse enough to be unambiguous, so only those are acted
  # on. Anything measured in days or weeks is left alone regardless of N.
  ollama list 2>/dev/null | sed 1d | while read -r name _ size unit rest; do
    local n_months=0
    case "$rest" in
      *year*)  n_months=12 ;;
      *month*) n_months="${rest%% *}" ;;
      *)       continue ;;
    esac
    [[ "$n_months" =~ ^[0-9]+$ ]] || continue
    if (( n_months * 30 >= OLLAMA_STALE_DAYS )); then
      if (( APPLY )); then ollama rm "$name" >/dev/null 2>&1 && ok "removed model $name ($size $unit)"
      else log "would remove model $name ($size $unit, $rest)"; fi
    fi
  done
}

# ── review ────────────────────────────────────────────────────
# Reported, never deleted. Each of these needs a judgement this script is not
# entitled to make.
review() {
  printf '\n'; log "needs a decision -- nothing below is touched by this script"

  # VM disks. Reclaiming one means destroying the VM and everything in it,
  # which is a decision, not a cleanup.
  local p vms=("$HOME/.colima" "$HOME/.lima" "$HOME/.docker/desktop")
  for p in "${vms[@]}"; do
    if [[ -d "$p" ]]; then
      warn "$(du -sh "$p" 2>/dev/null | cut -f1)  ${p/#$HOME/~} -- deleting this destroys the VM and anything in it"
    fi
  done

  # Large files inside project trees: models, archives, datasets. A 6 GB file
  # under ~/p is usually either committed by accident or genuinely the work.
  while IFS= read -r p; do
    warn "$(du -sh "$p" 2>/dev/null | cut -f1)  ${p/#$HOME/~} -- large file in a project tree"
  done < <(find "${PROJECT_DIRS[@]}" -type f -size +500M -not -path '*/.git/*' 2>/dev/null | head -10)

  # Project trees with no remote: the only copy is this disk, so "cleaning"
  # any of it is data loss, not cleanup.
  while IFS= read -r p; do
    local d; d="$(dirname "$p")"
    git -C "$d" remote 2>/dev/null | grep -q . || warn "$(du -sh -x "$d" 2>/dev/null | cut -f1)  ${d/#$HOME/~} -- git repo with NO remote, not backed up"
  done < <(find "${PROJECT_DIRS[@]}" -maxdepth 3 -type d -name .git -prune 2>/dev/null)

  # Repos whose .git has outgrown the working tree -- usually a large binary
  # committed once and carried forever. Only a history rewrite reclaims it.
  while IFS= read -r p; do
    local g; g="$(du -sk "$p" 2>/dev/null | cut -f1)"
    if [[ -n "$g" ]] && (( g > 2097152 )); then
      warn "$(human_kb "$g")  ${p/#$HOME/~} -- oversized history; needs a rewrite, see git-filter-repo"
    fi
  done < <(find "${PROJECT_DIRS[@]}" -maxdepth 3 -type d -name .git -prune 2>/dev/null)
}

# ── main ──────────────────────────────────────────────────────
main() {
  local before after
  before="$(avail_kb)"
  log "free before: $(human_kb "$before")  ($(df -h /System/Volumes/Data | tail -1 | awk '{print $5}') used)"

  if (( APPLY )) && (( ! ASSUME_YES )); then
    printf '\n'; warn "about to DELETE files in groups: ${TASK_GROUPS[*]}"
    read -r -p "  type 'yes' to continue: " reply
    [[ "$reply" == "yes" ]] || { err "aborted"; exit 1; }
  fi
  (( APPLY )) || log "DRY RUN -- nothing will be deleted (pass --apply)"
  printf '\n'

  wants caches && { clean_caches; printf '\n'; }
  wants builds && { clean_builds; printf '\n'; }
  wants docker && { prune_docker; printf '\n'; }
  wants models && { clean_models; printf '\n'; }

  review

  after="$(avail_kb)"
  printf '\n'
  if (( APPLY )); then
    ok "free after: $(human_kb "$after")  --  reclaimed $(human_kb $((after - before)))"
  else
    log "free: $(human_kb "$after")  (dry run; re-run with --apply)"
  fi
}

main "$@"
