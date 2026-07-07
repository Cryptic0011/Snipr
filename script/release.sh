#!/usr/bin/env bash
# One-command release: ./script/release.sh <version>
# Builds, signs, notarizes, staples the DMG; signs the update for Sparkle;
# appends an appcast entry; commits, tags, pushes; creates the GitHub
# release with the DMG attached.
#
# Requirements (all already provisioned on this machine):
#   - "Developer ID Application" identity in the keychain
#   - notarytool keychain profile "snipr-notary"
#   - Sparkle EdDSA private key in the login keychain (generate_keys)
#   - gh CLI authenticated
set -euo pipefail

VERSION="${1:?usage: release.sh <version>  (e.g. 0.2.0)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/dist/Snipr-$VERSION.dmg"
APPCAST="$ROOT_DIR/appcast.xml"
REPO_URL="https://github.com/Cryptic0011/Snipr"
TOOLS_DIR="$ROOT_DIR/script/.sparkle-tools"

cd "$ROOT_DIR"

if ! git diff-index --quiet HEAD --; then
  echo "Working tree is dirty; commit or stash before releasing." >&2
  exit 1
fi

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION already exists." >&2
  exit 1
fi

# Bootstrap Sparkle's signing tools if missing (they're gitignored).
if [[ ! -x "$TOOLS_DIR/bin/sign_update" ]]; then
  echo "Fetching Sparkle tools"
  mkdir -p "$TOOLS_DIR"
  URL=$(gh api repos/sparkle-project/Sparkle/releases/latest \
    --jq '.assets[] | select(.name | test("^Sparkle-[0-9.]+\\.tar\\.xz$")) | .browser_download_url')
  curl -sL "$URL" -o "$TOOLS_DIR/sparkle.tar.xz"
  tar -xf "$TOOLS_DIR/sparkle.tar.xz" -C "$TOOLS_DIR"
fi

echo "== Tests"
swift test

echo "== Build + sign + notarize DMG"
"$ROOT_DIR/script/build_dmg.sh" "$VERSION"

echo "== Sparkle update signature"
SIGNATURE="$("$TOOLS_DIR/bin/sign_update" "$DMG_PATH")"
echo "$SIGNATURE"

echo "== Appcast entry"
PUB_DATE="$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")"
ITEM_FILE="$(mktemp)"
cat >"$ITEM_FILE" <<ITEM
    <item>
      <title>Snipr $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$REPO_URL/releases/download/v$VERSION/Snipr-$VERSION.dmg"
        $SIGNATURE
        type="application/octet-stream"/>
    </item>
ITEM
sed -i '' "/<!-- RELEASES /r $ITEM_FILE" "$APPCAST"
rm -f "$ITEM_FILE"

echo "== Commit, tag, push"
git add "$APPCAST"
git commit -m "chore(release): v$VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"

echo "== GitHub release"
gh release create "v$VERSION" "$DMG_PATH" --title "Snipr $VERSION" --generate-notes

echo "Released v$VERSION"
echo "Sparkle clients will pick it up from $REPO_URL (appcast on main)."
