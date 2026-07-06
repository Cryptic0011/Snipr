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

SNIPR_VERSION="$VERSION" "$ROOT_DIR/script/build_and_run.sh" --build-only

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

echo "$DMG_PATH"
