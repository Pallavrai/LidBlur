#!/bin/bash
# Builds, signs, notarizes and staples LidBlur.app and LidBlur-<version>.dmg, then prints the cask checksum.
# Usage: DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=lidblur scripts/release.sh 0.1.0 1
# NOTARY_PROFILE is a keychain profile from `xcrun notarytool store-credentials`; no secrets live in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$1"
BUILD="${2:-1}"
: "${DEVELOPER_ID:?set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"
APP=dist/LidBlur.app
DMG="dist/LidBlur-$VERSION.dmg"

scripts/bundle.sh "$VERSION" "$BUILD"
# bundle.sh signs without a secure timestamp; notarization requires one.
codesign --force --options runtime --timestamp --entitlements App/LidBlur.entitlements --sign "$DEVELOPER_ID" "$APP"

ditto -c -k --keepParent "$APP" dist/LidBlur.zip
xcrun notarytool submit dist/LidBlur.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm dist/LidBlur.zip

rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname LidBlur -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

xcrun stapler validate "$DMG"
spctl -a -vv -t install "$DMG"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "version \"$VERSION\""
echo "sha256 \"$SHA\""
echo "Copy both lines into homebrew-lidblur/Casks/lidblur.rb and upload $DMG to the GitHub release v$VERSION."
