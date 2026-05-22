#!/bin/bash
#
# build-release.sh — Builds a Release Glide.app and zips it for sharing.
# Run from the repo root:  ./build-release.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/Glide"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_ZIP="$HOME/Desktop/Glide.zip"

# Extended attributes (Finder info, .DS_Store) propagate into the bundle and
# break codesign with "resource fork ... detritus not allowed".
echo "==> Cleaning extended attributes…"
xattr -cr "$PROJECT_DIR" 2>/dev/null || true
find "$PROJECT_DIR" -name '.DS_Store' -delete 2>/dev/null || true

# Build WITHOUT signing — Xcode's inline codesign step is the part that trips
# over detritus. We strip the finished bundle and sign it ourselves below.
echo "==> Building Glide (Release, unsigned)…"
cd "$PROJECT_DIR"
xcodebuild \
  -project Glide.xcodeproj \
  -scheme Glide \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_PATH="$BUILD_DIR/Build/Products/Release/Glide.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: build did not produce Glide.app at $APP_PATH"
  exit 1
fi

# Sign with the local Apple Development identity when present. Its designated
# requirement is certificate-based (not cdhash-based like ad-hoc), so an
# Accessibility/TCC grant survives rebuilds — the user only grants once.
# Falls back to ad-hoc if no Development identity is in the keychain.
SIGN_ID="$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')"
xattr -cr "$APP_PATH"
if [ -n "$SIGN_ID" ]; then
  echo "==> Signing (Apple Development: $SIGN_ID)…"
  codesign --force --deep --sign "$SIGN_ID" "$APP_PATH"
else
  echo "==> Signing (ad-hoc — no Development identity found)…"
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "==> Packaging…"
rm -f "$OUTPUT_ZIP"
# ditto preserves the .app bundle structure; a plain `zip` can corrupt it.
ditto -c -k --keepParent "$APP_PATH" "$OUTPUT_ZIP"

echo ""
echo "==> Done."
echo "Share this file with your friends: $OUTPUT_ZIP"
echo "They should follow the steps in DISTRIBUTION.md to install it."
