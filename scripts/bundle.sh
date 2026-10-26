#!/bin/bash
# Builds dist/LidBlur.app from the SwiftPM executable.
# Usage: scripts/bundle.sh [version] [build-number]
# Signs with $DEVELOPER_ID if set (hardened runtime), otherwise ad-hoc for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
BUILD="${2:-1}"
APP=dist/LidBlur.app

swift build -c release --arch arm64
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --arch arm64 --show-bin-path)/LidBlur" "$APP/Contents/MacOS/LidBlur"
cp App/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none \
  --entitlements App/LidBlur.entitlements \
  --sign "${DEVELOPER_ID:--}" "$APP"
codesign --verify --strict "$APP"
echo "$APP"
