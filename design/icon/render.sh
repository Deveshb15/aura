#!/usr/bin/env bash
# Reproducibly rebuild the Aura icon: SVG -> high-res PNG -> downscaled master.
# Requires: python3, Google Chrome, macOS `sips`.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 1. (re)generate the standalone SVG + HTML wrapper
python3 build_icon.py

# 2. rasterize at 2x for crispness -> 2048x2048 transparent PNG
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --force-device-scale-factor=2 \
  --window-size=1024,1024 --screenshot=aura-icon@2x.png preview.html

# 3. master 1024 (downscaled from 2x = sharper than a direct 1024 render)
sips -z 1024 1024 aura-icon@2x.png --out aura-icon.png >/dev/null

echo "Done -> aura-icon.svg, aura-icon.png (1024), aura-icon@2x.png (2048)"
