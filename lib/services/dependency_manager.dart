import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/config/app_config.dart';
import '../core/errors/app_error.dart';
import '../core/utils/platform_info.dart';
import '../models/dependency_status.dart';
import 'binary_installer.dart';
import 'ffmpeg_service.dart';
import 'process_service.dart';

final _log = Logger('dependencies');

/// Locates, validates, installs and updates yt-dlp and FFmpeg.
///
/// Resolution order (first valid wins):
/// 1. Custom path configured in Settings (never silently replaced).
/// 2. Copy installed by finder in the app data `bin` folder.
/// 3. Copy bundled inside the packaged application.
/// 4. `PATH` and well-known install locations.
class DependencyManager {
  DependencyManager({
    required this.platform,
    required this._processes,
    required this.managedBinDir,
    BinaryInstaller? installer,
  }) : _installer = installer ?? BinaryInstaller();

  final PlatformInfo platform;
  final ProcessService _processes;
  final String managedBinDir;
  final BinaryInstaller _installer;

  static final _ytDlpVersion = RegExp(r'^\d{4}\.\d{2}\.\d{2}(?:\.\d+)?');

  String executableName(DependencyKind kind) => '${kind.executableBase}${platform.exeSuffix}';

  /// yt-dlp is installed as the official "onedir" build on macOS and Windows.
  /// The single-file builds unpack themselves on every launch, which the OS
  /// re-scans each time (~30 s per call on macOS).
  ({String asset, String folder, String executable})? get ytDlpOnedir {
    if (platform.isMacOS) {
      return (
        asset: DependencySources.ytDlpMacAsset,
        folder: DependencySources.ytDlpMacFolder,
        executable: DependencySources.ytDlpMacExecutable,
      );
    }
    if (platform.isWindows) {
      return (
        asset: platform.arch == HostArch.arm64
            ? DependencySources.ytDlpWindowsArm64Asset
            : DependencySources.ytDlpWindowsX64Asset,
        folder: DependencySources.ytDlpWindowsFolder,
        executable: DependencySources.ytDlpWindowsExecutable,
      );
    }
    return null;
  }

  String? _onedirRelative() {
    final o = ytDlpOnedir;
    return o == null ? null : p.join(o.folder, o.executable);
  }

  String managedPath(DependencyKind kind) {
    final onedir = _onedirRelative();
    if (kind == DependencyKind.ytDlp && onedir != null) return p.join(managedBinDir, onedir);
    return p.join(managedBinDir, executableName(kind));
  }

  List<(String, DependencySource)> candidates(DependencyKind kind) {
    final name = executableName(kind);
    final seen = <String>{};
    final out = <(String, DependencySource)>[];
    void addPath(String path, DependencySource source) {
      if (seen.add(p.normalize(path))) out.add((path, source));
    }

    void add(String dir, DependencySource source) => addPath(p.join(dir, name), source);

    final onedir = kind == DependencyKind.ytDlp ? _onedirRelative() : null;
    if (onedir != null) addPath(p.join(managedBinDir, onedir), DependencySource.managed);
    add(managedBinDir, DependencySource.managed);
    for (final d in platform.bundledBinaryDirs) {
      if (onedir != null) addPath(p.join(d, onedir), DependencySource.bundled);
      add(d, DependencySource.bundled);
    }
    for (final d in platform.pathDirs) {
      add(d, DependencySource.system);
    }
    for (final d in platform.conventionalBinaryDirs) {
      add(d, DependencySource.system);
    }
    return out;
  }

  Future<DependencySnapshot> snapshot({String? ytDlpPath, String? ffmpegPath}) async {
    final results = await Future.wait([
      resolve(DependencyKind.ytDlp, customPath: ytDlpPath),
      resolve(DependencyKind.ffmpeg, customPath: ffmpegPath),
    ]);
    return DependencySnapshot(ytDlp: results[0], ffmpeg: results[1]);
  }

  Future<DependencyStatus> resolve(DependencyKind kind, {String? customPath}) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      return validate(kind, customPath.trim(), DependencySource.custom);
    }
    for (final (path, source) in candidates(kind)) {
      if (!await File(path).exists()) continue;
      final status = await validate(kind, path, source);
      if (status.isReady) return status;
      _log.info('skipping invalid ${kind.label} candidate (${source.name})');
    }
    return DependencyStatus.missing(kind, message: '${kind.label} was not found.');
  }

  /// Verifies that [path] is a real, runnable [kind] executable.
  Future<DependencyStatus> validate(
    DependencyKind kind,
    String path,
    DependencySource source,
  ) async {
    DependencyStatus invalid(String why) => DependencyStatus(
          kind: kind,
          state: DependencyState.invalid,
          path: path,
          source: source,
          message: why,
        );

    if (!p.isAbsolute(path)) return invalid('The path must be absolute.');
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      return invalid('No file exists at this path.');
    }
    final base = p.basenameWithoutExtension(path).toLowerCase();
    final expectedPrefix = kind == DependencyKind.ytDlp ? 'yt-dlp' : 'ffmpeg';
    if (!base.startsWith(expectedPrefix) && !base.startsWith(expectedPrefix.replaceAll('-', '_'))) {
      return invalid('The file name must start with "$expectedPrefix".');
    }
    if (platform.isWindows) {
      if (p.extension(path).toLowerCase() != '.exe') {
        return invalid('On Windows the executable must be an .exe file.');
      }
    } else {
      final mode = (await File(path).stat()).mode;
      if (mode & 0x49 == 0) {
        return invalid('The file is not executable. Allow execution (chmod +x) and re-check.');
      }
    }

    final versionArgs = kind == DependencyKind.ytDlp
        ? const ['--ignore-config', '--version']
        : const ['-hide_banner', '-version'];
    final ProcessOutcome outcome;
    try {
      // The first launch of a freshly installed binary can be slow while
      // macOS scans it; allow for that once.
      outcome = await _processes.run(path, versionArgs,
          timeout: kind == DependencyKind.ytDlp ? AppConfig.firstLaunchProbeTimeout : AppConfig.probeTimeout);
    } on ProcessException catch (e) {
      return invalid('The file could not be executed (${e.message}).');
    }
    if (outcome.timedOut) return invalid('The executable did not respond in time.');
    if (!outcome.ok) return invalid('The executable exited with code ${outcome.exitCode}.');

    final version = kind == DependencyKind.ytDlp
        ? _ytDlpVersion.firstMatch(outcome.stdout.trim())?.group(0)
        : FfmpegService.parseVersion(outcome.stdout);
    if (version == null) {
      return invalid('This doesn\'t appear to be ${kind.label}.');
    }
    if (kind == DependencyKind.ffmpeg) {
      final probe = FfmpegService.ffprobePathFor(path);
      if (!await File(probe).exists()) {
        return DependencyStatus(
          kind: kind,
          state: DependencyState.ready,
          path: path,
          version: version,
          source: source,
          message: 'ffprobe wasn\'t found next to ffmpeg; some post-processing may fail.',
        );
      }
    }
    return DependencyStatus(
      kind: kind,
      state: DependencyState.ready,
      path: path,
      version: version,
      source: source,
    );
  }

  /// Whether finder can download a verified official build on this OS.
  bool canInstall(DependencyKind kind) {
    if (kind == DependencyKind.ytDlp) return platform.isMacOS || platform.isWindows;
    // FFmpeg's project only publishes source; yt-dlp's FFmpeg-Builds provides
    // checksummed Windows binaries. No equivalent official macOS build exists.
    return platform.isWindows;
  }

  String guidance(DependencyKind kind) {
    if (kind == DependencyKind.ytDlp) {
      return 'Click "Install" to download the official yt-dlp release from GitHub. '
          'It is verified against the release\'s SHA-256 checksums before use. '
          'You can also download it yourself from ${DependencySources.ytDlpHomepage} '
          'and choose the file.';
    }
    if (platform.isWindows) {
      return 'Click "Install" to download a verified FFmpeg build from the official '
          'yt-dlp/FFmpeg-Builds release (GPL). Alternatively choose an existing ffmpeg.exe.';
    }
    return 'FFmpeg is needed to merge video and audio. Download a macOS build '
        'linked from ${DependencySources.ffmpegHomepage}, place ffmpeg and ffprobe '
        'in a folder, then click "Choose file" and select ffmpeg. If you already '
        'use a package manager, finder detects ffmpeg in /opt/homebrew/bin, '
        '/usr/local/bin and /opt/local/bin automatically.';
  }

  /// Installs or updates [kind] into [managedBinDir].
  Future<DependencyStatus> install(DependencyKind kind, {InstallProgress? onProgress}) async {
    if (!canInstall(kind)) {
      throw AppError(AppErrorKind.missingDependency, guidance(kind));
    }
    await Directory(managedBinDir).create(recursive: true);
    if (kind == DependencyKind.ytDlp) {
      await _installYtDlpOnedir(onProgress);
    } else {
      await _installFfmpegWindows(onProgress);
    }
    final status = await validate(kind, managedPath(kind), DependencySource.managed);
    if (!status.isReady) {
      throw AppError(AppErrorKind.missingDependency,
          'The installed ${kind.label} failed validation: ${status.message}');
    }
    _log.info('installed ${kind.label} ${status.version}');
    return status;
  }

  Future<void> _installYtDlpOnedir(InstallProgress? onProgress) async {
    final onedir = ytDlpOnedir!;
    final work = Directory(p.join(managedBinDir, '.yt-dlp-install'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);
    try {
      final archive = await _installer.installAsset(
        releaseBase: DependencySources.ytDlpReleaseBase,
        checksumsUrl: Uri.parse(DependencySources.ytDlpChecksums),
        assetName: onedir.asset,
        target: File(p.join(work.path, onedir.asset)),
        onProgress: onProgress,
      );
      onProgress?.call(null, 'Extracting');
      final staging = Directory(p.join(work.path, onedir.folder));
      await BinaryInstaller.extractZip(archive, staging);
      final exe = File(p.join(staging.path, onedir.executable));
      if (!await exe.exists()) {
        throw const AppError(AppErrorKind.unknown, 'The yt-dlp archive had an unexpected layout.');
      }
      await _makeExecutable(exe.path);
      // Swap the new build into place.
      final dest = Directory(p.join(managedBinDir, onedir.folder));
      if (await dest.exists()) await dest.delete(recursive: true);
      await staging.rename(dest.path);
      onProgress?.call(null, 'Checking (the first launch can take ~30 s)');
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  Future<void> _installFfmpegWindows(InstallProgress? onProgress) async {
    final asset = platform.arch == HostArch.arm64
        ? DependencySources.ffmpegWindowsArm64Asset
        : DependencySources.ffmpegWindowsX64Asset;
    final work = Directory(p.join(managedBinDir, '.ffmpeg-install'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);
    try {
      final archive = await _installer.installAsset(
        releaseBase: DependencySources.ffmpegReleaseBase,
        checksumsUrl: Uri.parse(DependencySources.ffmpegChecksums),
        assetName: asset,
        target: File(p.join(work.path, asset)),
        onProgress: onProgress,
      );
      onProgress?.call(null, 'Extracting');
      final extracted = Directory(p.join(work.path, 'x'));
      await BinaryInstaller.extractZip(archive, extracted);
      final files = await extracted.list(recursive: true).where((e) => e is File).cast<File>().toList();
      File? find(String name) =>
          files.where((f) => p.basename(f.path).toLowerCase() == name).firstOrNull;
      final ffmpeg = find('ffmpeg.exe');
      final ffprobe = find('ffprobe.exe');
      if (ffmpeg == null || ffprobe == null) {
        throw const AppError(AppErrorKind.unknown,
            'The FFmpeg archive didn\'t contain ffmpeg.exe and ffprobe.exe.');
      }
      await ffmpeg.copy(p.join(managedBinDir, 'ffmpeg.exe'));
      await ffprobe.copy(p.join(managedBinDir, 'ffprobe.exe'));
      final license = find('license.txt');
      if (license != null) await license.copy(p.join(managedBinDir, 'FFMPEG-LICENSE.txt'));
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  Future<void> _makeExecutable(String path) async {
    if (platform.isWindows) return;
    final r = await Process.run('/bin/chmod', ['755', path], runInShell: false);
    if (r.exitCode != 0) {
      throw AppError(AppErrorKind.permission, 'Couldn\'t mark the downloaded file as executable.',
          detail: '${r.stderr}');
    }
  }

  /// Updates yt-dlp when it is managed by finder (re-downloads latest).
  /// Other installations must be updated by whatever installed them.
  bool canUpdate(DependencyStatus status) =>
      status.isReady && status.source == DependencySource.managed && canInstall(status.kind);
}
