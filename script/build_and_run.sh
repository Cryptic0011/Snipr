#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Snipr"
BUNDLE_ID="com.grayson.snipr"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${SNIPR_VERSION:-0.1.0}"
SPARKLE_FEED_URL="https://raw.githubusercontent.com/Cryptic0011/Snipr/main/appcast.xml"
SPARKLE_PUBLIC_ED_KEY="GPa3gezkwPZ2JAkqkXxa3DDSirwWVGd7kr1/H1Uu0sY="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_NAME="SniprAppIcon"
APP_ICON_SOURCE="$ROOT_DIR/Flat Logo.png"
APP_ICONSET="$DIST_DIR/$APP_ICON_NAME.iconset"
APP_ICON_FILE="$APP_RESOURCES/$APP_ICON_NAME.icns"

find_signing_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '
    /"Apple Development:/ {
      print $2
      found = 1
      exit
    }
    /"Developer ID Application:/ && fallback == "" {
      fallback = $2
    }
    END {
      if (!found && fallback != "") {
        print fallback
      }
    }
  '
}

build_app_icon() {
  if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "Missing app icon source: $APP_ICON_SOURCE" >&2
    exit 1
  fi

  rm -rf "$APP_ICONSET"
  mkdir -p "$APP_ICONSET"
  /usr/bin/sips -z 16 16 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_512x512.png" >/dev/null
  /usr/bin/sips -z 1024 1024 "$APP_ICON_SOURCE" --out "$APP_ICONSET/icon_512x512@2x.png" >/dev/null
  /usr/bin/iconutil -c icns "$APP_ICONSET" -o "$APP_ICON_FILE"
  rm -rf "$APP_ICONSET"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
BUILD_CONFIG="${SNIPR_BUILD_CONFIG:-debug}"
swift build -c "$BUILD_CONFIG"
BUILD_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Sparkle ships as a binary xcframework; the bundle needs the framework
# embedded and an rpath so the binary can find it.
SPARKLE_FRAMEWORK="$(/usr/bin/find "$ROOT_DIR/.build/artifacts" -name Sparkle.framework -path "*macos*" -not -path "*dSYMs*" -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework not found under .build/artifacts" >&2
  exit 1
fi
mkdir -p "$APP_CONTENTS/Frameworks"
cp -a "$SPARKLE_FRAMEWORK" "$APP_CONTENTS/Frameworks/"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"

cp "$ROOT_DIR"/Sources/Snipr/Resources/*.png "$APP_RESOURCES"/
cp "$ROOT_DIR"/Sources/Snipr/Resources/Wallpapers/*.jpg "$APP_RESOURCES"/
build_app_icon

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Snipr records your microphone only when you enable it for a screen recording.</string>
  <key>NSCameraUsageDescription</key>
  <string>Snipr shows your camera in the webcam bubble only when you enable it for a screen recording.</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${SNIPR_CODESIGN_IDENTITY:-$(find_signing_identity)}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "Signing with: $SIGNING_IDENTITY"
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
else
  echo "Signing with ad-hoc identity; TCC permissions may reset after rebuilds." >&2
  /usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build-only|build-only)
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
