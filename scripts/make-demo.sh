#!/usr/bin/env bash
# Renders README media into dist/demo/: panel screenshots, demo.gif and demo.mp4 (needs ffmpeg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/demo"
cd "$ROOT"
rm -rf "$OUT" && mkdir -p "$OUT"
swift build
# Isolated Keychain area, and pretend the SmartThings CLI is installed, so the demo never reads
# your real sign-in and always shows the same screens.
env -u AERIS_CLIENT_ID -u AERIS_CLIENT_SECRET -u AERIS_TOKEN \
  AERIS_KEYCHAIN_SERVICE=com.kashmithnisakya.aeris.demo AERIS_ST_CLI=/usr/bin/true \
  AERIS_ST_CREDENTIALS=/dev/null AERIS_API=http://127.0.0.1:9 \
  AC_DEMO_OUT="$OUT" "$(swift build --show-bin-path)/Aeris"
if command -v ffmpeg >/dev/null; then
  (cd "$OUT" && ffmpeg -loglevel error -y -f concat -safe 0 -i frames.txt \
     -vf "fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" -c:v libx264 -movflags +faststart demo.mp4)
fi
rm -f "$OUT/frames.txt"; mkdir -p "$OUT/frames" && mv "$OUT"/frame-*.png "$OUT/frames/"
ls -la "$OUT"
