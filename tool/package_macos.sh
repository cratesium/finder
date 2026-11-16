#!/bin/sh
# Builds the macOS release app WITH yt-dlp and FFmpeg inside it, so users don't
# need to install anything, then packages it as a DMG (drag to Applications)
# and a zip.
#
#   tool/package_macos.sh                      # universal (Apple Silicon + Intel)
#   ARCH=arm64 tool/package_macos.sh           # smaller, single-architecture build
#   CODESIGN_IDENTITY="Developer ID Application: …" tool/package_macos.sh
#
# Notarization (optional, needs a Developer ID identity) — either:
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>
# or:
#   APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=<app-specific password>
#
# Without CODESIGN_IDENTITY the app is ad-hoc signed (fine for local use and
# testing; Gatekeeper will warn on other Macs).
# Output: build/release/Finder-<version>-macos.{dmg,zip}
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
ARCH="${ARCH:-universal}"
IDENTITY="${CODESIGN_IDENTITY:--}"
NAME="Finder"

# 1. Verified dependencies (downloaded once; delete third_party/macos to refresh).
if [ ! -x third_party/macos/bin/ffmpeg ] || [ ! -x third_party/macos/bin/yt-dlp_macos/yt-dlp_macos ]; then
  dart run tool/fetch_dependencies.dart --platform macos --arch "$ARCH"
fi

# 2. App
flutter build macos --release
APP="build/macos/Build/Products/Release/$NAME.app"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

# 3. Bundle into Finder.app/Contents/Resources/bin
echo "Bundling yt-dlp + FFmpeg into $APP/Contents/Resources/bin"
rm -rf "$APP/Contents/Resources/bin"
mkdir -p "$APP/Contents/Resources/bin"
cp -R third_party/macos/bin/ "$APP/Contents/Resources/bin/"

# yt-dlp's onedir zip stores Python.framework's symlinks as plain copies,
# which codesign rejects ("bundle format is ambiguous"). Restore the standard
# framework layout (Versions/Current, top-level Python/Resources as symlinks).
find "$APP/Contents/Resources/bin" -type d -name '*.framework' | while read -r fw; do
  name=$(basename "$fw" .framework)
  ver=$(ls "$fw/Versions" | grep -v '^Current$' | head -1)
  [ -n "$ver" ] || continue
  rm -rf "$fw/Versions/Current" && ln -s "$ver" "$fw/Versions/Current"
  for entry in "$name" Resources; do
    if [ -e "$fw/Versions/$ver/$entry" ]; then
      rm -rf "${fw:?}/$entry" && ln -s "Versions/Current/$entry" "$fw/$entry"
    fi
  done
done

# Every nested Mach-O must be signed (inside-out) for Gatekeeper/notarization:
# loose binaries first, then each framework as a bundle.
# The hardened runtime (required for notarization) enforces library
# validation: every dylib must carry the same Team ID as the executable. Ad-hoc
# signatures have no Team ID, so yt-dlp couldn't load its Python runtime; local
# ad-hoc builds therefore skip the hardened runtime.
TIMESTAMP="--timestamp=none"
RUNTIME=""
if [ "$IDENTITY" != "-" ]; then
  TIMESTAMP="--timestamp"
  RUNTIME="--options runtime"
fi
# Ad-hoc builds keep a binary's existing Developer ID signature (the FFmpeg
# build is notarized); an ad-hoc signature would make Gatekeeper block it.
keeps_signature() {
  [ "$IDENTITY" = "-" ] || return 1
  codesign --verify --strict "$1" >/dev/null 2>&1 || return 1
  codesign -dv "$1" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$'
}
find "$APP/Contents/Resources/bin" -type f -not -path '*.framework/*' | while read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    keeps_signature "$f" && continue
    codesign --force $RUNTIME $TIMESTAMP -s "$IDENTITY" "$f"
  fi
done
find "$APP/Contents/Resources/bin" -type d -name '*.framework' | while read -r fw; do
  codesign --force $RUNTIME $TIMESTAMP -s "$IDENTITY" "$fw"
done
codesign --force $RUNTIME $TIMESTAMP \
  --entitlements macos/Runner/Release.entitlements -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "Signed: $APP"

# 4. Self-check: the bundled tools run from inside the app.
"$APP/Contents/Resources/bin/ffmpeg" -hide_banner -version | head -1
"$APP/Contents/Resources/bin/yt-dlp_macos/yt-dlp_macos" --ignore-config --version

mkdir -p build/release
ZIP="build/release/$NAME-$VERSION-macos.zip"
DMG="build/release/$NAME-$VERSION-macos.dmg"

# 5. DMG: the app plus an Applications shortcut.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format ULFO -ov "$DMG" >/dev/null
[ "$IDENTITY" != "-" ] && codesign --force $TIMESTAMP -s "$IDENTITY" "$DMG"

# 6. Optional notarization + stapling (requires a Developer ID signature).
notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
  fi
}
if [ "$IDENTITY" != "-" ] && { [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${APPLE_ID:-}" ]; }; then
  echo "Notarizing $DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
else
  echo "Skipping notarization (needs CODESIGN_IDENTITY and NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD)"
fi

# 7. Zip (after stapling, so the ticket travels with the app).
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release: $DMG"
echo "Release: $ZIP"
ls -lh "$DMG" "$ZIP"
