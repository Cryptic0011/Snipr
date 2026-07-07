#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Snipr"
VERSION="${1:-0.1.0-test}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_ICON="$APP_BUNDLE/Contents/Resources/SniprAppIcon.icns"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

NOTARY_PROFILE="${SNIPR_NOTARY_PROFILE:-snipr-notary}"
SIGNING_IDENTITY="${SNIPR_CODESIGN_IDENTITY:-$(
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F\" '/"Developer ID Application:/ { print $2; exit }'
)}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No Developer ID Application identity found; a distributable DMG needs one." >&2
  exit 1
fi

SNIPR_VERSION="$VERSION" SNIPR_BUILD_CONFIG=release "$ROOT_DIR/script/build_and_run.sh" --build-only

echo "Signing app with: $SIGNING_IDENTITY"
/usr/bin/codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

/usr/bin/swift - "$APP_ICON" "$DMG_PATH" <<'SWIFT'
import AppKit
import Darwin

let iconPath = CommandLine.arguments[1]
let targetPath = CommandLine.arguments[2]

guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("Could not load icon at \(iconPath)\n", stderr)
    exit(1)
}

guard NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: []) else {
    fputs("Could not apply custom icon to \(targetPath)\n", stderr)
    exit(1)
}
SWIFT

rm -rf "$DMG_ROOT"

echo "Signing DMG"
/usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "Notarizing (profile: $NOTARY_PROFILE) — this can take a few minutes"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling ticket"
xcrun stapler staple "$DMG_PATH"

echo "Gatekeeper verification"
/usr/sbin/spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo "$DMG_PATH"
