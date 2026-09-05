#!/bin/sh
# CompressiusMaximus (cmx) installer — Linux / macOS.
# Downloads the signed release archive from the distribution host, verifies
# its checksum and installs a single static binary.
#
#   CMX_DIST_URL=https://dl.example.com sh install.sh
#
set -eu

DEST="${CMX_INSTALL_DIR:-$HOME/.local/bin}"
# GitHub Releases is the maintained public mirror. CMX_DIST_URL remains the
# explicit override for private, staging, or air-gapped mirrors.
BASE="${CMX_DIST_URL:-https://github.com/compressius/compressiusmaximus/releases/latest/download}"

# --- platform ----------------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux) GOOS=linux ;;
  darwin) GOOS=darwin ;;
  *) echo "error: unsupported OS: $OS" >&2; exit 1 ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) GOARCH=amd64 ;;
  aarch64|arm64) GOARCH=arm64 ;;
  *) echo "error: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

ASSET="cmx_${GOOS}_${GOARCH}.tar.gz"
URL="${BASE%/}/${ASSET}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

INTERACTIVE=0
[ -t 1 ] && INTERACTIVE=1

stage() {
  printf '\n==> %s\n' "$1"
}

download() {
  download_url="$1"
  download_file="$2"
  shift 2
  if command -v curl >/dev/null 2>&1; then
    if [ "$INTERACTIVE" = 1 ]; then
      curl -fL --progress-bar "$@" -o "$download_file" "$download_url"
    else
      curl -fsSL "$@" -o "$download_file" "$download_url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ "$INTERACTIVE" = 1 ]; then
      wget --show-progress "$@" -O "$download_file" "$download_url"
    else
      wget -q "$@" -O "$download_file" "$download_url"
    fi
  else
    echo "error: need curl or wget" >&2
    exit 1
  fi
}

stage "Downloading CMX"
if command -v curl >/dev/null 2>&1; then
  if [ -n "${CMX_GITHUB_TOKEN:-}" ]; then
    download "$URL" "$TMP/$ASSET" -H "Authorization: Bearer $CMX_GITHUB_TOKEN"
  else
    download "$URL" "$TMP/$ASSET"
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -n "${CMX_GITHUB_TOKEN:-}" ]; then
    download "$URL" "$TMP/$ASSET" --header="Authorization: Bearer $CMX_GITHUB_TOKEN"
  else
    download "$URL" "$TMP/$ASSET"
  fi
else
  echo "error: need curl or wget" >&2; exit 1
fi

# --- checksum ----------------------------------------------------------------
SHA_URL="${BASE%/}/latest.json"
stage "Verifying download"
download "$SHA_URL" "$TMP/latest.json"
WANT="$(sed -n "s/.*\"url\"[[:space:]]*:[[:space:]]*\"${ASSET}\".*\"sha256\"[[:space:]]*:[[:space:]]*\"\([a-f0-9][a-f0-9]*\)\".*/\1/p" "$TMP/latest.json" | head -1)"
if [ "${#WANT}" -ne 64 ]; then
  echo "error: manifest has no valid checksum for $ASSET" >&2
  exit 1
fi
case "$WANT" in
  *[!0123456789abcdef]*) echo "error: invalid checksum for $ASSET" >&2; exit 1 ;;
esac
if command -v sha256sum >/dev/null 2>&1; then
  GOT="$(sha256sum "$TMP/$ASSET" | cut -d' ' -f1)"
elif command -v shasum >/dev/null 2>&1; then
  GOT="$(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)"
else
  echo "error: need sha256sum or shasum for checksum verification" >&2
  exit 1
fi
[ "$GOT" = "$WANT" ] || { echo "error: checksum mismatch ($GOT != $WANT)" >&2; exit 1; }
echo "    checksum verified"

stage "Installing CMX"
tar -xzf "$TMP/$ASSET" -C "$TMP"
BIN="$TMP/cmx"
[ -f "$BIN" ] || BIN="$TMP/cmx_${GOOS}_${GOARCH}/cmx"
[ -f "$BIN" ] || { echo "error: binary not found in archive" >&2; exit 1; }

mkdir -p "$DEST"
install -m 0755 "$BIN" "$DEST/cmx"

case ":$PATH:" in
  *":$DEST:"*) COMMAND="cmx" ;;
  *) COMMAND="$DEST/cmx" ;;
esac

GATEWAY_STATE="not started"
SERVICE_STATE="not installed"
stage "Starting gateway"
if [ "${CMX_SKIP_START:-0}" = 1 ]; then
  GATEWAY_STATE="not started (skipped)"
  echo "    skipped (CMX_SKIP_START=1)"
else
  if "$DEST/cmx" start; then
    GATEWAY_STATE="running"
    echo "    gateway running"
  else
    GATEWAY_STATE="not running (start failed)"
    echo "warning: gateway did not start; run '$DEST/cmx start' after installation" >&2
  fi
fi
if [ "$(uname -s)" = "Linux" ] && [ "${CMX_INSTALL_SERVICE:-1}" = 1 ] && [ "${CMX_SKIP_START:-0}" != 1 ]; then
  stage "Installing user service"
  if "$DEST/cmx" service install >/dev/null 2>&1; then
    SERVICE_STATE="installed (per-user systemd)"
  else
    echo "    service install skipped or unavailable"
  fi
fi

printf '\n'
printf '%s\n' '╭─ CMX installed ─────────────────────────────────'
printf '%s\n' "│ Installed: $DEST/cmx"
printf '%s\n' "│ Gateway:   $GATEWAY_STATE"
[ "$SERVICE_STATE" = "not installed" ] || printf '%s\n' "│ Service:   $SERVICE_STATE"
printf '%s\n' "│ Open TUI:  $COMMAND"
printf '%s\n' "│ Helpful:   $COMMAND status · $COMMAND setup · $COMMAND help"
printf '%s\n' '╰────────────────────────────────────────────────'
if [ "$COMMAND" != "cmx" ]; then
  printf '%s\n' "Add CMX to PATH, then restart your shell: export PATH=\"$DEST:\$PATH\""
fi
