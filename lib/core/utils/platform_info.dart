import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

enum HostOs { macos, windows, linux, android, ios, other }

enum HostArch { arm64, x64, other }

/// Abstraction over the host platform so services are testable.
class PlatformInfo {
  const PlatformInfo({
    required this.os,
    required this.arch,
    required this.resolvedExecutable,
    required this.environment,
  });

  factory PlatformInfo.current() {
    final os = Platform.isMacOS
        ? HostOs.macos
        : Platform.isWindows
        ? HostOs.windows
        : Platform.isAndroid
        ? HostOs.android
        : Platform.isLinux
        ? HostOs.linux
        : Platform.isIOS
        ? HostOs.ios
        : HostOs.other;
    final abi = Abi.current();
    final arch = switch (abi) {
      Abi.macosArm64 || Abi.windowsArm64 || Abi.linuxArm64 || Abi.androidArm64 || Abi.iosArm64 => HostArch.arm64,
      Abi.macosX64 || Abi.windowsX64 || Abi.linuxX64 || Abi.androidX64 || Abi.iosX64 => HostArch.x64,
      _ => HostArch.other,
    };
    return PlatformInfo(
      os: os,
      arch: arch,
      resolvedExecutable: Platform.resolvedExecutable,
      environment: Map.unmodifiable(Platform.environment),
    );
  }

  final HostOs os;
  final HostArch arch;
  final String resolvedExecutable;
  final Map<String, String> environment;

  bool get isWindows => os == HostOs.windows;
  bool get isMacOS => os == HostOs.macos;
  bool get isAndroid => os == HostOs.android;
  bool get isLinux => os == HostOs.linux;

  /// iOS can't start child processes: it uses the built-in engine in
  /// `services/ios/` (YouTube extraction in Dart, muxing with AVFoundation).
  bool get isIOS => os == HostOs.ios;

  /// Phones and tablets (no folder picker, system share UI).
  bool get isMobile => isAndroid || isIOS;

  /// Desktop platforms run yt-dlp/FFmpeg as native child processes. On Android
  /// they are embedded in the APK and run through the platform channel.
  bool get isDesktop => isMacOS || isWindows || os == HostOs.linux;

  String get exeSuffix => isWindows ? '.exe' : '';

  String get label {
    final o = switch (os) {
      HostOs.macos => 'macOS',
      HostOs.windows => 'Windows',
      HostOs.linux => 'Linux',
      HostOs.android => 'Android',
      HostOs.ios => 'iOS',
      HostOs.other => 'Unknown OS',
    };
    final a = switch (arch) {
      HostArch.arm64 => isMacOS ? 'Apple Silicon (arm64)' : 'arm64',
      HostArch.x64 => isMacOS ? 'Intel (x64)' : 'x64',
      HostArch.other => 'unknown arch',
    };
    return '$o · $a';
  }

  /// Directories in which bundled binaries are looked up inside a packaged app.
  ///
  /// * macOS: `Finder.app/Contents/Resources/bin`
  /// * Windows: `<install dir>\bin` next to `finder.exe`
  /// * Linux: `<bundle>/bin` next to the `finder` executable (also inside
  ///   the AppImage and under `/opt/finder` for .deb/.rpm installs;
  ///   [resolvedExecutable] is the real path, not the `/usr/bin` symlink)
  List<String> get bundledBinaryDirs {
    final exeDir = p.dirname(resolvedExecutable);
    if (isMacOS) {
      return [p.normalize(p.join(exeDir, '..', 'Resources', 'bin'))];
    }
    return [p.join(exeDir, 'bin'), exeDir];
  }
}
