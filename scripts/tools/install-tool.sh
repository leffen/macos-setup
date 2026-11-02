#!/usr/bin/env bash
#
# install-tool.sh — install or upgrade velero, flux, talosctl, kubectl or helm.
#
# Use it when one of those on your PATH is behind the cluster or upstream.
# It installs the exact version you name, or the latest, into a
# user-local bin directory — no sudo, no package manager, no conflict with a
# system or Homebrew copy beyond PATH ordering.
#
#   scripts/install-tool.sh velero 1.16.0   # an exact version
#   scripts/install-tool.sh flux            # whatever upstream calls latest
#   scripts/install-tool.sh all             # every tool, at latest
#   scripts/install-tool.sh --list          # what is installed vs latest
#
# Env:
#   HCV_BIN_DIR   install target (default: $HOME/.local/bin)
#   GITHUB_TOKEN  optional, only to raise the GitHub API rate limit
#
# Every download is checksum-verified against the publisher's own checksum
# file; the install is refused if it does not match.
#
# ── Coexistence with the Brewfile ─────────────────────────────
# flux, helm, kubernetes-cli and velero also come from the Brewfile, and
# talosctl from an (untrusted, currently failing) tap. That overlap is
# deliberate: brew gives a working baseline, this gives an exact version when
# one is needed. ~/.local/bin is first on PATH (dotfiles/zshenv), so anything
# installed here silently wins over the brew copy -- which is the point, and
# also the thing to remember when a version looks wrong. `which -a <tool>`
# settles it.

set -euo pipefail

BIN_DIR="${HCV_BIN_DIR:-$HOME/.local/bin}"
TOOLS=(velero flux talosctl kubectl helm)

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }

# ---------------------------------------------------------------- platform ---

detect_os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux)  echo linux ;;
    *)      die "unsupported OS: $(uname -s)" ;;
  esac
}

detect_arch() {
  # A shell running under Rosetta reports x86_64 on an arm64 Mac; ask the
  # kernel about the actual hardware before trusting uname.
  if [ "$(uname -s)" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    echo arm64; return
  fi
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo amd64 ;;
    *)             die "unsupported architecture: $(uname -m)" ;;
  esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

# ------------------------------------------------------------------ github ---

# gh_curl — curl with the token attached when one is set. Written as two
# calls rather than an argument array because macOS ships bash 3.2, where
# expanding an empty array under `set -u` is an error.
gh_curl() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --max-time 30 -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    curl -fsSL --max-time 30 "$@"
  fi
}

# gh_latest <owner/repo> — newest release tag, without the leading "v".
gh_latest() {
  local repo=$1 body tag
  body=$(gh_curl "https://api.github.com/repos/$repo/releases/latest") \
    || die "could not reach the GitHub API for $repo (rate limited? set GITHUB_TOKEN)"
  tag=$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$tag" ] || die "no release tag found for $repo"
  printf '%s' "${tag#v}"
}

latest_version() {
  case "$1" in
    velero)   gh_latest vmware-tanzu/velero ;;
    flux)     gh_latest fluxcd/flux2 ;;
    talosctl) gh_latest siderolabs/talos ;;
    helm)     gh_latest helm/helm ;;
    kubectl)  curl -fsSL --max-time 30 https://dl.k8s.io/release/stable.txt | sed 's/^v//' ;;
    *)        die "unknown tool: $1" ;;
  esac
}

# --------------------------------------------------------------- installed ---

# version_of <tool> <path> — the version that specific binary reports.
version_of() {
  local tool=$1 bin=$2
  [ -x "$bin" ] || { echo ""; return; }
  case "$tool" in
    velero)   "$bin" version --client-only 2>/dev/null | sed -n 's/^[[:space:]]*Version:[[:space:]]*v\{0,1\}//p' | head -1 ;;
    flux)     "$bin" version --client 2>/dev/null | sed -n 's/^flux:[[:space:]]*v\{0,1\}//p' | head -1 ;;
    talosctl) "$bin" version --client 2>/dev/null | sed -n 's/^[[:space:]]*Tag:[[:space:]]*v\{0,1\}//p' | head -1 ;;
    kubectl)  "$bin" version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1 ;;
    helm)     "$bin" version --short 2>/dev/null | sed -n 's/^v\{0,1\}\([0-9][^+]*\).*/\1/p' | head -1 ;;
  esac
}

# installed_version <tool> — the version a version check will see, i.e. the copy that wins
# on PATH. This is what the report compares against, so it is what we display.
installed_version() {
  local bin
  bin="$(command -v "$1" 2>/dev/null || true)"
  [ -n "$bin" ] || { echo ""; return; }
  version_of "$1" "$bin"
}

# ----------------------------------------------------------------- sources ---
# Each tool sets: URL, CHECKSUM_URL, CHECKSUM_NAME (file named in the checksum
# list, empty when the file is a bare hash) and ARCHIVE ("tar" or "raw").

source_for() {
  local tool=$1 v=$2
  case "$tool" in
    velero)
      local base="https://github.com/vmware-tanzu/velero/releases/download/v$v"
      ASSET="velero-v$v-$OS-$ARCH.tar.gz"
      URL="$base/$ASSET"; CHECKSUM_URL="$base/CHECKSUM"; CHECKSUM_NAME="$ASSET"
      ARCHIVE=tar; ARCHIVE_PATH="velero-v$v-$OS-$ARCH/velero" ;;
    flux)
      local base="https://github.com/fluxcd/flux2/releases/download/v$v"
      ASSET="flux_${v}_${OS}_${ARCH}.tar.gz"
      URL="$base/$ASSET"; CHECKSUM_URL="$base/flux_${v}_checksums.txt"; CHECKSUM_NAME="$ASSET"
      ARCHIVE=tar; ARCHIVE_PATH="flux" ;;
    talosctl)
      local base="https://github.com/siderolabs/talos/releases/download/v$v"
      ASSET="talosctl-$OS-$ARCH"
      URL="$base/$ASSET"; CHECKSUM_URL="$base/sha256sum.txt"; CHECKSUM_NAME="$ASSET"
      ARCHIVE=raw ;;
    kubectl)
      local base="https://dl.k8s.io/release/v$v/bin/$OS/$ARCH"
      URL="$base/kubectl"; CHECKSUM_URL="$base/kubectl.sha256"; CHECKSUM_NAME=""
      ARCHIVE=raw ;;
    helm)
      ASSET="helm-v$v-$OS-$ARCH.tar.gz"
      URL="https://get.helm.sh/$ASSET"; CHECKSUM_URL="https://get.helm.sh/$ASSET.sha256sum"
      CHECKSUM_NAME="$ASSET"; ARCHIVE=tar; ARCHIVE_PATH="$OS-$ARCH/helm" ;;
    *) die "unknown tool: $1" ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ----------------------------------------------------------------- install ---

install_tool() {
  local tool=$1 want=${2:-} have
  [ -n "$want" ] || want="$(latest_version "$tool")"
  want="${want#v}"

  # Decide from the copy in BIN_DIR, not from whatever wins on PATH: a
  # different (older, brew-managed, system) binary earlier on PATH must not
  # make a pinned install silently no-op.
  local here; here="$(version_of "$tool" "$BIN_DIR/$tool")"
  if [ "$here" = "$want" ] && [ "${FORCE:-0}" != "1" ]; then
    info "$tool is already $want ($BIN_DIR/$tool) — nothing to do"
    return 0
  fi

  # Report whichever copy this install replaces: the one in BIN_DIR if there
  # is one, otherwise whatever a version check currently sees on PATH.
  have="$here"
  [ -n "$have" ] || have="$(installed_version "$tool")"

  source_for "$tool" "$want"
  info "$tool ${have:-(not installed)} -> $want   [$OS/$ARCH]"

  local tmp; tmp="$(mktemp -d)"; TMP_DIR="$tmp"

  curl -fsSL --max-time 300 -o "$tmp/download" "$URL" \
    || die "download failed: $URL"

  local want_sum got_sum
  want_sum=$(curl -fsSL --max-time 60 "$CHECKSUM_URL" \
    || die "could not fetch checksums: $CHECKSUM_URL")
  if [ -n "$CHECKSUM_NAME" ]; then
    want_sum=$(printf '%s\n' "$want_sum" | awk -v f="$CHECKSUM_NAME" '$2 == f || $2 == "*"f {print $1; exit}')
  else
    want_sum=$(printf '%s\n' "$want_sum" | awk '{print $1; exit}')
  fi
  [ -n "$want_sum" ] || die "no checksum published for ${CHECKSUM_NAME:-$tool} in $CHECKSUM_URL"

  got_sum=$(sha256_of "$tmp/download")
  [ "$got_sum" = "$want_sum" ] \
    || die "checksum mismatch for $tool $want: got $got_sum, expected $want_sum"

  if [ "$ARCHIVE" = tar ]; then
    tar -xzf "$tmp/download" -C "$tmp" "$ARCHIVE_PATH" \
      || die "could not extract $ARCHIVE_PATH from $ASSET"
    mv "$tmp/$ARCHIVE_PATH" "$tmp/$tool"
  else
    mv "$tmp/download" "$tmp/$tool"
  fi

  mkdir -p "$BIN_DIR"
  chmod +x "$tmp/$tool"
  # Same-filesystem rename keeps the swap atomic, so a half-written binary is
  # never left on PATH.
  mv "$tmp/$tool" "$BIN_DIR/$tool"

  rm -rf "$tmp"; TMP_DIR=""
  info "installed $tool $want -> $BIN_DIR/$tool"

  local first_on_path; first_on_path="$(command -v "$tool" 2>/dev/null || true)"
  if [ -n "$first_on_path" ] && [ "$first_on_path" != "$BIN_DIR/$tool" ]; then
    warn "$first_on_path still comes first on PATH; put $BIN_DIR ahead of it:"
    warn "    export PATH=\"$BIN_DIR:\$PATH\""
  fi
}

list_tools() {
  printf '%-10s %-14s %-14s %s\n' TOOL INSTALLED LATEST PATH
  local t have want
  for t in "${TOOLS[@]}"; do
    have="$(installed_version "$t")"
    # `die` exits the command substitution outright, so the fallback has to
    # live outside it — `$(... || echo ?)` would never run.
    want="$(latest_version "$t" 2>/dev/null)" || want='?'
    [ -n "$want" ] || want='?' 
    printf '%-10s %-14s %-14s %s\n' \
      "$t" "${have:--}" "$want" "$(command -v "$t" 2>/dev/null || echo '-')"
  done
}

usage() {
  sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# -------------------------------------------------------------------- main ---

need curl
need tar

FORCE=0
TMP_DIR=""
trap 'rm -rf "${TMP_DIR:-}"' EXIT

WANT_TOOL=""
WANT_VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) FORCE=1 ;;
    -l|--list)  list_tools; exit 0 ;;
    -h|--help)  usage 0 ;;
    -*)         die "unknown flag: $1 (try --help)" ;;
    *)
      if [ -z "$WANT_TOOL" ]; then WANT_TOOL="$1"
      elif [ -z "$WANT_VERSION" ]; then WANT_VERSION="$1"
      else die "unexpected argument: $1"
      fi ;;
  esac
  shift
done

[ -n "$WANT_TOOL" ] || usage 1

if [ "$WANT_TOOL" = all ]; then
  for t in "${TOOLS[@]}"; do install_tool "$t"; done
else
  printf '%s\n' "${TOOLS[@]}" | grep -qx "$WANT_TOOL" \
    || die "unknown tool: $WANT_TOOL (known: ${TOOLS[*]})"
  install_tool "$WANT_TOOL" "$WANT_VERSION"
fi
