#!/bin/bash
# Builds dist/LidBlur.app and dist/LidBlur-<version>.dmg, and updates Casks/lidblur.rb with the DMG checksum.
#
# Usage: scripts/build.sh [version] [build-number]
#
# Signing is chosen by environment:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"   sign with hardened runtime
#   NOTARY_PROFILE=<profile from `xcrun notarytool store-credentials`>   also notarize and staple
# Without them the build is ad-hoc signed, which is fine for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)}"
BUILD="${2:-1}"
SIGN="${DEVELOPER_ID:--}"
APP=dist/LidBlur.app
DMG="dist/LidBlur-$VERSION.dmg"

swift build -c release --arch arm64
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/LidBlur" "$APP/Contents/MacOS/"
cp App/Info.plist "$APP/Contents/"
cp App/AppIcon.icns "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

TIMESTAMP=--timestamp
[ "$SIGN" = "-" ] && TIMESTAMP=--timestamp=none
codesign --force --options runtime $TIMESTAMP --entitlements App/LidBlur.entitlements --sign "$SIGN" "$APP"
codesign --verify --strict "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$APP" dist/LidBlur.zip
  xcrun notarytool submit dist/LidBlur.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm dist/LidBlur.zip
fi

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname LidBlur -srcfolder "$STAGE" -format UDZO "$DMG"
rm -rf "$STAGE"

if [ "$SIGN" != "-" ]; then codesign --sign "$SIGN" --timestamp "$DMG"; fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -vv -t install "$DMG"
fi

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/lidblur.rb
echo "$DMG"
echo "sha256 $SHA (written to Casks/lidblur.rb)"
