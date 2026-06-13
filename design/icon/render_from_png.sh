#!/usr/bin/env bash
# Rasterize the Carpet app icon slots from the source raster art.
#
# Supersedes the old SVG pipeline (build_icon.py / render.sh), which generated
# the previous "Notch Sprite" mark. The brand art is now a finished PNG
# (assets/logo.png), so we just center-crop it to a square master and downscale
# to each AppIcon slot with `sips`.
#
# Usage: design/icon/render_from_png.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/assets/logo.png"
OUT="$ROOT/Aura/Assets.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Center-crop to a square master (logo.png is ~1036x1050 → crop to 1036²).
DIM="$(sips -g pixelWidth -g pixelHeight "$SRC" | awk '/pixel/{print $2}' | sort -n | head -1)"
MASTER="$TMP/master.png"
sips -c "$DIM" "$DIM" "$SRC" --out "$MASTER" >/dev/null

# 2) Emit each AppIcon slot at its pixel size.
emit() { sips -z "$2" "$2" "$MASTER" --out "$OUT/$1" >/dev/null; echo "  $1 (${2}px)"; }
echo "Rendering AppIcon slots → $OUT"
emit AppIcon-16.png      16
emit AppIcon-16@2x.png   32
emit AppIcon-32.png      32
emit AppIcon-32@2x.png   64
emit AppIcon-128.png     128
emit AppIcon-128@2x.png  256
emit AppIcon-256.png     256
emit AppIcon-256@2x.png  512
emit AppIcon-512.png     512
emit AppIcon-512@2x.png  1024
echo "Done."
