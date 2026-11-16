#!/usr/bin/env bash
# Builds the Linux release WITH yt-dlp and FFmpeg inside it, then packages it
# as an AppImage, a .deb and (when rpmbuild is available) an .rpm. Run on Linux.
#
#   tool/package_linux.sh                 # host architecture (x64 or arm64)
#   SKIP_BUILD=1 tool/package_linux.sh    # repackage an existing bundle
#   FORMATS="deb rpm" tool/package_linux.sh
#
# Build requirements (Debian/Ubuntu):
#   clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev unzip xz-utils
#   file imagemagick (icons) dpkg-dev (deb) rpm (rpm)
# appimagetool is downloaded automatically when not on PATH.
#
# Output: build/release/Finder-<version>-linux-<arch>.{AppImage,deb,rpm}
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
BUILD_NUMBER=$(sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)
BUILD_NUMBER=${BUILD_NUMBER:-1}
FORMATS="${FORMATS:-appimage deb rpm}"
APP_ID="com.cratesium.app"
NAME="Finder"
BIN="finder"

case "$(uname -m)" in
  x86_64|amd64) ARCH=x64; DEB_ARCH=amd64; RPM_ARCH=x86_64; AI_ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64; DEB_ARCH=arm64; RPM_ARCH=aarch64; AI_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

BUNDLE="build/linux/$ARCH/release/bundle"
OUT="build/release"
WORK="build/linux-package"
mkdir -p "$OUT"
rm -rf "$WORK"
mkdir -p "$WORK"

# 1. Verified dependencies (downloaded once; delete third_party/linux to refresh).
YTDLP_EXE=yt-dlp_linux
[ "$ARCH" = arm64 ] && YTDLP_EXE=yt-dlp_linux_aarch64
if [ ! -x third_party/linux/bin/ffmpeg ] || [ ! -x "third_party/linux/bin/yt-dlp_linux/$YTDLP_EXE" ]; then
  rm -rf third_party/linux
  dart run tool/fetch_dependencies.dart --platform linux --arch "$ARCH"
fi

# 2. App (CMake installs third_party/linux/bin into the bundle's bin/).
if [ -z "${SKIP_BUILD:-}" ]; then
  flutter build linux --release
fi
[ -x "$BUNDLE/$BIN" ] || { echo "missing $BUNDLE/$BIN" >&2; exit 1; }
[ -x "$BUNDLE/bin/ffmpeg" ] || { echo "bundled FFmpeg missing from $BUNDLE/bin" >&2; exit 1; }

# 3. Self-check: the bundled tools run on this system.
"$BUNDLE/bin/ffmpeg" -hide_banner -version | head -1
"$BUNDLE/bin/yt-dlp_linux/$YTDLP_EXE" --ignore-config --version

# 4. Shared desktop integration files.
ICONS="$WORK/icons"
mkdir -p "$ICONS"
if command -v magick >/dev/null; then IM=(magick); else IM=(convert); fi
for size in 16 32 48 64 128 256 512; do
  mkdir -p "$ICONS/${size}x${size}/apps"
  "${IM[@]}" assets/icons/app_icon_1024.png -resize "${size}x${size}" "$ICONS/${size}x${size}/apps/$APP_ID.png"
done
DESKTOP="$WORK/$APP_ID.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
GenericName=Video Downloader
Comment=Download videos and playlists
Exec=$BIN %U
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Network;
Keywords=video;playlist;download;youtube;audio;
StartupWMClass=$APP_ID
EOF

install_tree() { # <root> <prefix for app files>
  local root="$1" appdir="$2"
  mkdir -p "$root$appdir" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons"
  cp -a "$BUNDLE/." "$root$appdir/"
  ln -sf "$appdir/$BIN" "$root/usr/bin/$BIN"
  cp "$DESKTOP" "$root/usr/share/applications/"
  cp -a "$ICONS" "$root/usr/share/icons/hicolor"
}

# 5. .deb
if [[ " $FORMATS " == *" deb "* ]]; then
  ROOT="$WORK/deb"
  install_tree "$ROOT" /opt/finder
  mkdir -p "$ROOT/DEBIAN"
  SIZE=$(du -sk "$ROOT" | cut -f1)
  cat > "$ROOT/DEBIAN/control" <<EOF
Package: finder
Version: $VERSION-$BUILD_NUMBER
Section: video
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $SIZE
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libstdc++6
Maintainer: Finder <support@Finder.app>
Homepage: https://cratesium.app
Description: Finder — video and playlist downloader
 Download single videos or whole playlists in the quality you choose.
 yt-dlp and FFmpeg are bundled; nothing else has to be installed.
EOF
  cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
EOF
  cp "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"
  chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"
  DEB="$OUT/$NAME-$VERSION-linux-$ARCH.deb"
  dpkg-deb --root-owner-group --build "$ROOT" "$DEB"
  echo "Release: $DEB"
fi

# 6. .rpm
if [[ " $FORMATS " == *" rpm "* ]]; then
  if command -v rpmbuild >/dev/null; then
    TOP="$(pwd)/$WORK/rpm"
    mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    STAGE="$TOP/stage"
    install_tree "$STAGE" /opt/finder
    cat > "$TOP/SPECS/finder.spec" <<EOF
Name:           finder
Version:        $VERSION
Release:        $BUILD_NUMBER
Summary:        Video and playlist downloader
License:        Proprietary; bundles yt-dlp (Unlicense) and FFmpeg (GPL)
URL:            https://cratesium.app
BuildArch:      $RPM_ARCH
Requires:       gtk3
# The bundled yt-dlp/FFmpeg carry their own libraries; don't derive
# requirements or provides from them.
AutoReqProv:    no
%global __os_install_post %{nil}
%global debug_package %{nil}

%description
Download single videos or whole playlists in the quality you choose.
yt-dlp and FFmpeg are bundled; nothing else has to be installed.

%install
cp -a "$STAGE/." %{buildroot}/

%files
/opt/finder
/usr/bin/finder
/usr/share/applications/$APP_ID.desktop
/usr/share/icons/hicolor/*/apps/$APP_ID.png

%post
update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || :
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || :

%postun
update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || :
EOF
    rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/finder.spec" >/dev/null
    RPM="$OUT/$NAME-$VERSION-linux-$ARCH.rpm"
    cp "$TOP/RPMS/$RPM_ARCH/"*.rpm "$RPM"
    echo "Release: $RPM"
  else
    echo "rpmbuild not found; skipping .rpm" >&2
  fi
fi

# 7. AppImage
if [[ " $FORMATS " == *" appimage "* ]]; then
  APPDIR="$WORK/$NAME.AppDir"
  mkdir -p "$APPDIR/usr"
  cp -a "$BUNDLE" "$APPDIR/usr/lib-finder"
  cp "$DESKTOP" "$APPDIR/$APP_ID.desktop"
  cp "$ICONS/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
  mkdir -p "$APPDIR/usr/share/icons"
  cp -a "$ICONS" "$APPDIR/usr/share/icons/hicolor"
  cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib-finder/finder" "$@"
EOF
  chmod 755 "$APPDIR/AppRun"
  TOOL="$(command -v appimagetool || true)"
  if [ -z "$TOOL" ]; then
    TOOL="$WORK/appimagetool"
    curl -fsSL -o "$TOOL" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$AI_ARCH.AppImage"
    chmod 755 "$TOOL"
  fi
  APPIMAGE="$OUT/$NAME-$VERSION-linux-$ARCH.AppImage"
  # Extract-and-run works in containers/CI without FUSE.
  ARCH="$AI_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$APPIMAGE"
  echo "Release: $APPIMAGE"
fi

ls -lh "$OUT"/*linux-"$ARCH"* 2>/dev/null || true
