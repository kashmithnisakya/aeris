#!/usr/bin/env bash
# Aeris installer: downloads the latest release and installs it into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/kashmithnisakya/aeris/main/install.sh | bash
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/kashmithnisakya/aeris/main/install.sh | bash -s -- --uninstall
#
# Options (env vars): AERIS_INSTALL_DIR (default /Applications), AERIS_NO_OPEN=1 (don't launch after install)
set -euo pipefail

REPO="kashmithnisakya/aeris"
APP="Aeris.app"
DEST="${AERIS_INSTALL_DIR:-/Applications}"
URL="https://github.com/$REPO/releases/latest/download/Aeris.zip"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Aeris only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || fail "Aeris needs macOS 13 Ventura or later."

SUDO=""
if [ -e "$DEST" ] && [ ! -w "$DEST" ]; then SUDO="sudo"; fi

if [ "${1:-}" = "--uninstall" ]; then
  info "Removing $DEST/$APP"
  pkill -x Aeris 2>/dev/null || true
  $SUDO rm -rf "$DEST/$APP"
  security delete-generic-password -s com.kashmithnisakya.aeris.smartthings >/dev/null 2>&1 || true
  defaults delete com.kashmithnisakya.aeris >/dev/null 2>&1 || true
  info "Aeris uninstalled (saved token and settings removed)."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "Downloading the latest Aeris"
curl -fL --progress-bar "$URL" -o "$tmp/Aeris.zip" || fail "Download failed: $URL"
ditto -x -k "$tmp/Aeris.zip" "$tmp/unpacked"
[ -d "$tmp/unpacked/$APP" ] || fail "The download didn't contain $APP."

info "Installing to $DEST"
pkill -x Aeris 2>/dev/null || true
$SUDO mkdir -p "$DEST"
$SUDO rm -rf "$DEST/$APP"
$SUDO ditto "$tmp/unpacked/$APP" "$DEST/$APP"
# The app isn't notarized; clearing quarantine avoids the "unidentified developer" prompt.
$SUDO xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

version="$(defaults read "$DEST/$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"
info "Aeris $version installed. Look for the AC icon in your menu bar."

if [ "${AERIS_NO_OPEN:-0}" != "1" ]; then
  open "$DEST/$APP"
fi
