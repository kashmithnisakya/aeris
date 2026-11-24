#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Aeris.app and a zip for release.
# Usage: scripts/build-app.sh [version]
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Aeris.app"

cd "$ROOT"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Building $VERSION (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Aeris"
cp "$BIN" "$APP/Contents/MacOS/Aeris"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Aeris</string>
  <key>CFBundleDisplayName</key><string>Aeris</string>
  <key>CFBundleIdentifier</key><string>com.kashmithnisakya.aeris</string>
  <key>CFBundleExecutable</key><string>Aeris</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Making app icon"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$DIST/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$DIST/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$DIST/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$DIST/icon-1024.png"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Zipping"
(cd "$DIST" && ditto -c -k --keepParent "Aeris.app" "Aeris-$VERSION.zip")
# Fixed name so install.sh and the Homebrew cask can use releases/latest/download/Aeris.zip
cp "$DIST/Aeris-$VERSION.zip" "$DIST/Aeris.zip"
echo "Done: $DIST/Aeris-$VERSION.zip (+ Aeris.zip)"
