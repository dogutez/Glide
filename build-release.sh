#!/bin/bash
#
# build-release.sh — Builds a Release Glide.app and zips it for sharing.
# Run from the repo root:  ./build-release.sh [--install]
#   --install  also replaces /Applications/Glide.app and relaunches it
#
set -euo pipefail

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

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

# Sign and package from a temp folder outside the repo. Extended attributes make
# codesign fail with "resource fork ... detritus not allowed", and on the iCloud
# Desktop the file provider keeps re-adding com.apple.FinderInfo to the bundle,
# so stripping it in place is a race. Copy without xattrs/resource forks instead.
echo "==> Staging a clean copy…"
STAGE="$(mktemp -d -t glidebuild)"
trap 'rm -rf "$STAGE"' EXIT
SIGNED_APP="$STAGE/Glide.app"
ditto --norsrc --noextattr --noqtn "$APP_PATH" "$SIGNED_APP"

if [ -n "$SIGN_ID" ]; then
  echo "==> Signing (Apple Development: $SIGN_ID)…"
  codesign --force --deep --sign "$SIGN_ID" "$SIGNED_APP"
else
  echo "==> Signing (ad-hoc — no Development identity found)…"
  codesign --force --deep --sign - "$SIGNED_APP"
fi
codesign --verify --deep --strict "$SIGNED_APP"

echo "==> Packaging…"
rm -f "$OUTPUT_ZIP"
# ditto preserves the .app bundle structure; a plain `zip` can corrupt it.
ditto -c -k --norsrc --keepParent "$SIGNED_APP" "$OUTPUT_ZIP"

if [ "$INSTALL" = 1 ]; then
  echo "==> Installing to /Applications and relaunching…"
  pkill -x Glide 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Glide.app
  ditto --norsrc --noextattr --noqtn "$SIGNED_APP" /Applications/Glide.app
  open /Applications/Glide.app
fi

echo ""
echo "==> Done."
echo "Share this file with your friends: $OUTPUT_ZIP"
echo "They should follow the steps in DISTRIBUTION.md to install it."
