import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

enum HostOs { macos, windows, linux, other }

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
            : Platform.isLinux
                ? HostOs.linux
                : HostOs.other;
    final abi = Abi.current();
    final arch = switch (abi) {
      Abi.macosArm64 || Abi.windowsArm64 || Abi.linuxArm64 => HostArch.arm64,
      Abi.macosX64 || Abi.windowsX64 || Abi.linuxX64 => HostArch.x64,
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

  String get exeSuffix => isWindows ? '.exe' : '';

  String get label {
    final o = switch (os) {
      HostOs.macos => 'macOS',
      HostOs.windows => 'Windows',
      HostOs.linux => 'Linux',
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
  /// * macOS: `CourseGrab.app/Contents/Resources/bin`
  /// * Windows: `<install dir>\bin` next to `coursegrab.exe`
  List<String> get bundledBinaryDirs {
    final exeDir = p.dirname(resolvedExecutable);
    if (isMacOS) {
      return [p.normalize(p.join(exeDir, '..', 'Resources', 'bin'))];
    }
    return [p.join(exeDir, 'bin'), exeDir];
  }

  /// Well-known install locations that GUI apps don't get on their PATH.
  List<String> get conventionalBinaryDirs {
    if (isMacOS) {
      final home = environment['HOME'];
      return [
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/opt/local/bin',
        if (home != null) p.join(home, '.local', 'bin'),
        if (home != null) p.join(home, 'bin'),
      ];
    }
    if (isWindows) {
      final local = environment['LOCALAPPDATA'];
      final userProfile = environment['USERPROFILE'];
      return [
        if (local != null) p.join(local, 'Microsoft', 'WinGet', 'Links'),
        if (userProfile != null) p.join(userProfile, 'scoop', 'shims'),
        r'C:\ProgramData\chocolatey\bin',
        r'C:\ffmpeg\bin',
      ];
    }
    return ['/usr/local/bin', '/usr/bin'];
  }

  List<String> get pathDirs {
    final path = environment['PATH'] ?? environment['Path'] ?? '';
    return path
        .split(isWindows ? ';' : ':')
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }
}
