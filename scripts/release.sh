#!/bin/bash
#
# Builds, signs, packages (and optionally notarizes) Aura for distribution.
#
#   ./scripts/release.sh                 # build + Developer ID sign app + signed DMG
#   NOTARY_PROFILE=AuraNotary ./scripts/release.sh   # also notarize + staple app & DMG
#
# Prereqs:
#   - "Developer ID Application: … (728M4WMSGG)" in the login keychain.
#   - For notarization, a stored notarytool keychain profile, created once with:
#       xcrun notarytool store-credentials "AuraNotary" \
#         --apple-id "<your-apple-id>" --team-id "728M4WMSGG" --password "<app-specific-password>"
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Aura"
SCHEME="Aura"
SIGN_ID="Developer ID Application: Pratyush Singh (728M4WMSGG)"
ENTITLEMENTS="Aura/Aura.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

BUILD_DIR="build/release"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DIST_DIR="dist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
STAGING="$BUILD_DIR/dmg-staging"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }

step "Regenerating project + building Release (unsigned)"
xcodegen generate >/dev/null
xcodebuild -project Aura.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO clean build 2>&1 | tail -3

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

step "Building the DMG (drag-to-Applications)"
mkdir -p "$DIST_DIR"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
rm -f "$DMG_PATH"
if ! create-dmg \
      --volname "$APP_NAME" \
      --window-size 540 380 \
      --icon-size 110 \
      --icon "$APP_NAME.app" 150 195 \
      --app-drop-link 390 195 \
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

step "Verification"
echo "App  codesign: $(codesign --verify --strict "$APP_PATH" 2>&1 && echo OK)"
set +e
echo "App  Gatekeeper:"; spctl -a -vvv -t exec "$APP_PATH" 2>&1 | sed 's/^/  /'
echo "DMG  Gatekeeper:"; spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | sed 's/^/  /'
set -e

printf '\n\033[1;32m✔ Done →\033[0m %s\n' "$DMG_PATH"
if [ -z "$NOTARY_PROFILE" ]; then
  echo "  (signed only — set NOTARY_PROFILE to also notarize + staple)"
fi
