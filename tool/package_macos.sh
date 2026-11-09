#!/bin/sh
# Builds the macOS release app and bundles verified dependencies.
#
#   dart run tool/fetch_dependencies.dart --platform macos [--ffmpeg /path/to/ffmpeg]
#   CODESIGN_IDENTITY="Developer ID Application: …" tool/package_macos.sh
#
# Without CODESIGN_IDENTITY the app is ad-hoc signed (fine for local use; use a
# Developer ID + notarization for distribution).
set -eu
cd "$(dirname "$0")/.."

flutter build macos --release
APP="build/macos/Build/Products/Release/finder.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [ -d third_party/macos/bin ]; then
  echo "Bundling dependencies into $APP/Contents/Resources/bin"
  rm -rf "$APP/Contents/Resources/bin"
  mkdir -p "$APP/Contents/Resources/bin"
  cp -R third_party/macos/bin/ "$APP/Contents/Resources/bin/"
  # Every nested Mach-O must be signed (inside-out) for Gatekeeper/notarization.
  find "$APP/Contents/Resources/bin" -type f | while read -r f; do
    if file "$f" | grep -q "Mach-O"; then
      codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$f"
    fi
  done
  codesign --force --options runtime --timestamp=none \
    --entitlements macos/Runner/Release.entitlements -s "$IDENTITY" "$APP"
fi

codesign --verify --deep --strict "$APP" && echo "Signed: $APP"
