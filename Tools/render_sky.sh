#!/usr/bin/env bash
# Rasterize Tools/sky.svg → Tools/sky.png (1320×840, the DMG @2x size), cover-cropped
# to the 660×420 installer window's aspect — mirroring the marketing site's `.sky-bg`.
#
# The sky's cloud `feTurbulence` filters only render faithfully in a real browser
# engine, so we use headless Google Chrome (same approach as design/icon/render.sh).
# Run this only when sky.svg changes; sky.png is committed so release.sh needs no Chrome.
#
# Usage: bash Tools/render_sky.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"   # → Tools/

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome not found at $CHROME" >&2; exit 1; }
[ -f sky.svg ] || { echo "missing Tools/sky.svg" >&2; exit 1; }

"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=660,420 \
  --screenshot=sky.png sky-render.html >/dev/null 2>&1

echo "wrote Tools/sky.png ($(sips -g pixelWidth -g pixelHeight sky.png | awk '/pixel/{printf "%s ",$2}'))"
