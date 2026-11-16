#!/bin/sh
# Xcode build phase: embeds the built-in engine (yt-dlp + FFmpeg) into
# Finder.app/Contents/Resources/bin on EVERY macOS build, so `flutter run` and
# `flutter build macos` produce a self-contained app — no Homebrew needed.
#
# The verified binaries are downloaded once into third_party/macos/bin
# (delete that folder to refresh). FINDER_DEPS_ARCH=arm64|x64 picks a smaller
# single-architecture download; the default is universal.
set -eu

ROOT="$PROJECT_DIR/.."
SRC="$ROOT/third_party/macos/bin"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin"
STAMP="$DEST/.embedded"

if [ ! -x "$SRC/ffmpeg" ] || [ ! -x "$SRC/yt-dlp_macos/yt-dlp_macos" ]; then
  echo "Finder: downloading the built-in engine (one time)…"
  (cd "$ROOT" && "$FLUTTER_ROOT/bin/dart" run tool/fetch_dependencies.dart \
    --platform macos --arch "${FINDER_DEPS_ARCH:-universal}") || {
    echo "error: Finder: couldn't download yt-dlp/FFmpeg. Check the network, or run" \
      "'dart run tool/fetch_dependencies.dart --platform macos' manually." >&2
    exit 1
  }
fi

# Up to date already (same source and script, already signed)?
if [ -f "$STAMP" ] && [ -z "$(find "$SRC" "$0" -newer "$STAMP" -print -quit)" ]; then
  exit 0
fi

echo "Finder: embedding yt-dlp + FFmpeg into the app"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/" "$DEST/"

# yt-dlp's onedir zip stores Python.framework's symlinks as plain copies, which
# codesign rejects. Restore the standard framework layout.
find "$DEST" -type d -name '*.framework' | while read -r fw; do
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

# Sign nested code inside-out (Xcode signs the app itself afterwards). Ad-hoc
# signatures skip the hardened runtime: without a Team ID, library validation
# would stop yt-dlp from loading its own Python runtime.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$IDENTITY" ] || IDENTITY="-"
RUNTIME=""
[ "$IDENTITY" = "-" ] || RUNTIME="--options runtime"
# Ad-hoc builds keep a binary's existing Developer ID signature (the macOS
# FFmpeg build is signed and notarized): replacing it with an ad-hoc one would
# make Gatekeeper block it on any other Mac.
keeps_signature() {
  [ "$IDENTITY" = "-" ] || return 1
  codesign --verify --strict "$1" >/dev/null 2>&1 || return 1
  codesign -dv "$1" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$'
}
find "$DEST" -type f -not -path '*.framework/*' | while read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    keeps_signature "$f" && continue
    codesign --force $RUNTIME --timestamp=none -s "$IDENTITY" "$f"
  fi
done
find "$DEST" -type d -name '*.framework' | while read -r fw; do
  codesign --force $RUNTIME --timestamp=none -s "$IDENTITY" "$fw"
done

touch "$STAMP"
