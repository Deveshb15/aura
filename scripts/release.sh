#!/bin/bash
#
# Builds, signs, notarizes, and packages Aura for distribution — and, because the
# app now ships Sparkle, also EdDSA-signs the DMG and regenerates the appcast feed.
#
#   ./scripts/release.sh                              # build + Developer ID sign + signed DMG + appcast
#   NOTARY_PROFILE=touchgrass-notary ./scripts/release.sh   # also notarize + staple app & DMG
#
# Prereqs:
#   - "Developer ID Application: … (728M4WMSGG)" in the login keychain.
#   - Sparkle EdDSA private key in the login keychain (from `generate_keys`, one-time).
#   - For notarization, a stored notarytool keychain profile, created once with:
#       xcrun notarytool store-credentials "touchgrass-notary" \
#         --apple-id "<your-apple-id>" --team-id "728M4WMSGG" --password "<app-specific-password>"
#
# After it runs, upload dist/Carpet-<version>.dmg to the matching GitHub Release and
# commit the regenerated docs/appcast.xml — the appcast's enclosure URL already
# points at that release asset.
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Carpet"
SCHEME="Aura"   # XcodeGen target/scheme name is still "Aura"; product is Carpet.app via PRODUCT_NAME
SIGN_ID="Developer ID Application: Pratyush Singh (728M4WMSGG)"
ENTITLEMENTS="Aura/Aura.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
REPO="Deveshb15/aura"

VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"

BUILD_DIR="build/release"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DIST_DIR="dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$BUILD_DIR/dmg-staging"
APPCAST_DIR="$DIST_DIR/appcast"
DL_PREFIX="https://github.com/$REPO/releases/download/v$VERSION/"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }

step "Regenerating project + building Release (unsigned) — $APP_NAME $VERSION"
xcodegen generate >/dev/null
# Universal (arm64 + x86_64) so Intel Macs are supported too; the AI-answer
# layer is runtime-gated to Apple Silicon, the rest works everywhere.
xcodebuild -project Aura.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO clean build 2>&1 | tail -3

# Locate Sparkle's CLI tools (downloaded as an SPM binary artifact).
SPARKLE_BIN="$(find "$BUILD_DIR/SourcePackages/artifacts" "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*Sparkle*/bin/generate_appcast' 2>/dev/null | head -1 | xargs -I{} dirname {})"
[ -n "$SPARKLE_BIN" ] || { echo "Sparkle tools not found"; exit 1; }

step "Signing Sparkle's helpers inside-out (hardened runtime on every Mach-O)"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
# XPC services exist only for sandboxed hosts; sign them if present so notarization
# never trips over an un-hardened nested binary.
for xpc in "$SPARKLE_FW/Versions/B/XPCServices/"*.xpc; do
  [ -e "$xpc" ] && codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$xpc"
done
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW"

step "Signing the embedded native-messaging helper (aura-x-host)"
# A nested Mach-O in Contents/MacOS must be signed before the outer bundle, or
# the app-level codesign fails with "code object is not signed at all". No app
# entitlements — it's a standalone stdio host.
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP_PATH/Contents/MacOS/aura-x-host"

step "Code-signing the app (Developer ID + Hardened Runtime + secure timestamp)"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_ID" \
  "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
echo "Signed by: $(codesign -dvv "$APP_PATH" 2>&1 | grep '^Authority' | head -1)"

if [ -n "$NOTARY_PROFILE" ]; then
  step "Notarizing the app"
  ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$APP_NAME.zip"
  xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  step "Stapling the app"
  xcrun stapler staple "$APP_PATH"
fi

step "Rendering the DMG background (Aura dark serif art)"
mkdir -p "$DIST_DIR"
swift Tools/DMGBackground.swift
tiffutil -cathidpicheck dist/dmg-bg-1x.png dist/dmg-bg-2x.png -out dist/dmg-bg.tiff >/dev/null

step "Building the DMG (drag-to-Applications)"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
rm -f "$DMG_PATH"
# Drop-zone coords must match Tools/DMGBackground.swift (app 180,205 — Applications 480,205).
if ! create-dmg \
      --volname "$APP_NAME" \
      --background "dist/dmg-bg.tiff" \
      --window-size 660 420 \
      --icon-size 128 \
      --text-size 13 \
      --icon "$APP_NAME.app" 180 205 \
      --app-drop-link 480 205 \
      --hdiutil-quiet \
      "$DMG_PATH" "$STAGING" 2>/dev/null; then
  echo "create-dmg styling failed; falling back to plain hdiutil DMG"
  ln -sf /Applications "$STAGING/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
fi

step "Signing the DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG_PATH"

if [ -n "$NOTARY_PROFILE" ]; then
  step "Notarizing + stapling the DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

step "Generating the Sparkle appcast (EdDSA-signed, → docs/appcast.xml)"
rm -rf "$APPCAST_DIR"; mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/"
# Optional per-version release notes shown in the update panel.
NOTES="$DIST_DIR/notes/$VERSION.html"
EMBED=()
if [ -f "$NOTES" ]; then cp "$NOTES" "$APPCAST_DIR/$APP_NAME-$VERSION.html"; EMBED=(--embed-release-notes); fi
mkdir -p docs
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DL_PREFIX" \
  --link "https://github.com/$REPO" \
  --maximum-versions 5 \
  ${EMBED[@]+"${EMBED[@]}"} \
  -o docs/appcast.xml \
  "$APPCAST_DIR"
echo "appcast → docs/appcast.xml (enclosure: ${DL_PREFIX}$(basename "$DMG_PATH"))"

step "Verification"
echo "App  codesign: $(codesign --verify --strict "$APP_PATH" 2>&1 && echo OK)"
set +e
echo "App  Gatekeeper:"; spctl -a -vvv -t exec "$APP_PATH" 2>&1 | sed 's/^/  /'
echo "DMG  Gatekeeper:"; spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | sed 's/^/  /'
set -e

printf '\n\033[1;32m✔ Done →\033[0m %s\n' "$DMG_PATH"
echo "  Next: gh release create v$VERSION \"$DMG_PATH\" --title \"$APP_NAME $VERSION\" --latest"
echo "        git add docs/appcast.xml && git commit -m \"appcast: v$VERSION\" && git push"
if [ -z "$NOTARY_PROFILE" ]; then
  echo "  (signed only — set NOTARY_PROFILE to also notarize + staple)"
fi
