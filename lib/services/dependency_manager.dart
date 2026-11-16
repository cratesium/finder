import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/config/app_config.dart';
import '../core/errors/app_error.dart';
import '../core/utils/platform_info.dart';
import '../models/dependency_status.dart';
import 'android/android_toolchain.dart';
import 'binary_installer.dart';
import 'ffmpeg_service.dart';
import 'process_service.dart';

final _log = Logger('dependencies');

/// Locates, validates, installs and updates yt-dlp and FFmpeg.
///
/// Finder ships both tools inside the app, so nothing has to be installed on
/// the computer and tools installed on the system are never used. Resolution
/// order (first valid wins):
/// 1. Custom path configured in Settings (never silently replaced).
/// 2. A newer yt-dlp downloaded by Finder's in-app "Update" (app data `bin`).
/// 3. The copies bundled inside the application package.
/// 4. macOS only: a private copy of the bundled engine in the app data folder,
///    made when macOS refuses to run the bundled copy in place (a quarantined
///    app opened from Downloads runs from a read-only, translocated location).
///
/// On Android both tools are embedded in the APK and run through
/// [AndroidToolchain]; they are always "bundled".
class DependencyManager {
  DependencyManager({
    required this.platform,
    required this._processes,
    required this.managedBinDir,
    this.android,
    BinaryInstaller? installer,
  }) : _installer = installer ?? BinaryInstaller();

  final PlatformInfo platform;
  final ProcessService _processes;
  final String managedBinDir;
  final AndroidToolchain? android;
  final BinaryInstaller _installer;

  bool get _isAndroid => platform.isAndroid && android != null;

  /// Private copy of the bundled engine (macOS fallback, see class docs).
  String get engineCopyDir => p.join(p.dirname(managedBinDir), 'engine');

  Future<void>? _quarantineCleared;
  Future<String?>? _engineCopy;

  static final _ytDlpVersion = RegExp(r'^\d{4}\.\d{2}\.\d{2}(?:\.\d+)?');

  String executableName(DependencyKind kind) => '${kind.executableBase}${platform.exeSuffix}';

  /// yt-dlp is installed as the official "onedir" build on macOS, Windows and
  /// Linux.
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
    if (platform.isLinux) {
      final arm = platform.arch == HostArch.arm64;
      return (
        asset: arm ? DependencySources.ytDlpLinuxArm64Asset : DependencySources.ytDlpLinuxX64Asset,
        folder: DependencySources.ytDlpLinuxFolder,
        executable: arm ? DependencySources.ytDlpLinuxArm64Executable : DependencySources.ytDlpLinuxX64Executable,
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
    if (_isAndroid) return _resolveAndroid(kind);
    if (customPath != null && customPath.trim().isNotEmpty) {
      return validate(kind, customPath.trim(), DependencySource.custom);
    }
    if (platform.isMacOS) await (_quarantineCleared ??= _clearBundledQuarantine());
    DependencyStatus? bundledFailure;
    for (final (path, source) in candidates(kind)) {
      if (!await File(path).exists()) continue;
      final status = await validate(kind, path, source);
      if (status.isReady) return status;
      _log.warning('skipping invalid ${kind.label} candidate (${source.name}): ${status.message}');
      if (source == DependencySource.bundled) bundledFailure ??= status;
    }
    if (platform.isMacOS) {
      final copy = await (_engineCopy ??= _copyBundledEngine());
      if (copy != null) {
        final onedir = kind == DependencyKind.ytDlp ? _onedirRelative() : null;
        final path = p.join(copy, onedir ?? executableName(kind));
        if (await File(path).exists()) {
          final status = await validate(kind, path, DependencySource.bundled);
          if (status.isReady) return status;
          _log.warning('private copy of ${kind.label} failed: ${status.message}');
          bundledFailure ??= status;
        }
      }
    }
    if (bundledFailure != null) {
      return DependencyStatus(
        kind: kind,
        state: DependencyState.invalid,
        path: bundledFailure.path,
        source: DependencySource.bundled,
        message: 'The built-in ${kind.label} couldn\'t start: ${bundledFailure.message}',
      );
    }
    return DependencyStatus.missing(
      kind,
      message: '${kind.label} is missing from this installation of ${AppConfig.appName}.',
    );
  }

  String? get _bundledDir {
    for (final d in platform.bundledBinaryDirs) {
      if (Directory(d).existsSync()) return d;
    }
    return null;
  }

  /// Apps downloaded from the internet carry a quarantine flag that macOS
  /// copies onto every file inside them; Gatekeeper then refuses to start the
  /// embedded tools. The user already approved the app itself, so the flag is
  /// removed from the engine inside it (best effort: the app may be read-only).
  Future<void> _clearBundledQuarantine() async {
    final dir = _bundledDir;
    if (dir == null) return;
    try {
      await Process.run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', dir], runInShell: false);
    } catch (e) {
      _log.fine('could not clear quarantine on the built-in engine', e);
    }
  }

  /// Copies the bundled engine into [engineCopyDir] without the quarantine
  /// flag. Reused across launches until the app's engine changes.
  Future<String?> _copyBundledEngine() async {
    final src = _bundledDir;
    if (src == null) return null;
    try {
      final stamp = await _bundleStamp(src);
      final dest = Directory(engineCopyDir);
      final stampFile = File(p.join(dest.path, '.source'));
      if (await stampFile.exists() && await stampFile.readAsString() == stamp) return dest.path;

      _log.info('copying the built-in engine to the app data folder');
      final staging = Directory('${dest.path}.tmp');
      if (await staging.exists()) await staging.delete(recursive: true);
      final r = await Process.run('/usr/bin/ditto', ['--noqtn', src, staging.path], runInShell: false);
      if (r.exitCode != 0) {
        _log.warning('copying the built-in engine failed: ${r.stderr}');
        if (await staging.exists()) await staging.delete(recursive: true);
        return null;
      }
      await Process.run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', staging.path], runInShell: false);
      await File(p.join(staging.path, '.source')).writeAsString(stamp, flush: true);
      if (await dest.exists()) await dest.delete(recursive: true);
      await staging.rename(dest.path);
      return dest.path;
    } catch (e) {
      _log.warning('copying the built-in engine failed', e);
      return null;
    }
  }

  /// Identifies the bundled engine build (changes when the app is updated).
  Future<String> _bundleStamp(String dir) async {
    final parts = <String>[];
    for (final rel in [?_onedirRelative(), executableName(DependencyKind.ffmpeg)]) {
      final f = File(p.join(dir, rel));
      if (!await f.exists()) continue;
      final st = await f.stat();
      parts.add('$rel:${st.size}:${st.modified.millisecondsSinceEpoch}');
    }
    return parts.join('|');
  }

  Future<DependencyStatus> _resolveAndroid(DependencyKind kind) async {
    DependencyStatus failed(String why) => DependencyStatus(
      kind: kind,
      state: DependencyState.invalid,
      path: kind == DependencyKind.ytDlp ? AndroidBundled.ytDlpPath : AndroidBundled.ffmpegPath,
      source: DependencySource.bundled,
      message: why,
    );
  Future<DependencyStatus> probe() async {
      try {
        await android!.ensureReady();
      } catch (e) {
        return failed('The built-in engine isn\'t ready yet: $e');
      }
      try {
        final String? version;
        if (kind == DependencyKind.ytDlp) {
          final r = await _processes.run(AndroidBundled.ytDlpPath, const [
            '--ignore-config',
            '--version',
          ], timeout: AppConfig.firstLaunchProbeTimeout);
          final combined = '${r.stdout}\n${r.stderr}'.trim();
          version = _ytDlpVersion.firstMatch(combined)?.group(0);
          if (!r.ok && version == null) {
            return failed(
              r.timedOut
                  ? 'The embedded yt-dlp did not respond in time (first launch can take a minute).'
                  : 'The embedded yt-dlp failed to start (exit ${r.exitCode}).',
            );
          }
        } else {
          final out = await android!.ffmpegVersion();
          version = out == null || out.trim().isEmpty ? null : FfmpegService.parseVersion(out);
        }
        return DependencyStatus(
          kind: kind,
          state: DependencyState.ready,
          path: kind == DependencyKind.ytDlp ? AndroidBundled.ytDlpPath : AndroidBundled.ffmpegPath,
          version: version ?? 'bundled',
          source: DependencySource.bundled,
        );
      } catch (e) {
        _log.warning('embedded ${kind.label} unavailable', e);
        return failed('The embedded ${kind.label} could not be started.');
      }
    }

    const delays = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)];
    DependencyStatus? last;
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      last = await probe();
      if (last.isReady) return last;
    }
    return last!;
  }

  /// Verifies that [path] is a real, runnable [kind] executable.
  Future<DependencyStatus> validate(DependencyKind kind, String path, DependencySource source) async {
    DependencyStatus invalid(String why) =>
        DependencyStatus(kind: kind, state: DependencyState.invalid, path: path, source: source, message: why);

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
      outcome = await _processes.run(
        path,
        versionArgs,
        timeout: kind == DependencyKind.ytDlp ? AppConfig.firstLaunchProbeTimeout : AppConfig.probeTimeout,
      );
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
    return DependencyStatus(kind: kind, state: DependencyState.ready, path: path, version: version, source: source);
  }

  /// Whether Finder can download a verified official build on this OS.
  bool canInstall(DependencyKind kind) {
    if (kind == DependencyKind.ytDlp) {
      return platform.isMacOS || platform.isWindows || platform.isLinux || _isAndroid;
    }
    // FFmpeg's project only publishes source; yt-dlp's FFmpeg-Builds provides
    // checksummed Windows and Linux binaries. On macOS the verified build is
    // bundled at packaging time (tool/fetch_dependencies.dart).
    return platform.isWindows || platform.isLinux;
  }

  String guidance(DependencyKind kind) {
    const reinstall =
        '${AppConfig.appName} ships with yt-dlp and FFmpeg built in. '
        'If one is missing, the installation is incomplete: reinstall ${AppConfig.appName}.';
    if (_isAndroid) return reinstall;
    if (kind == DependencyKind.ytDlp) {
      return '$reinstall You can also click "Install" to download the official, '
          'SHA-256-verified yt-dlp release into the app.';
    }
    if (platform.isWindows || platform.isLinux) {
      return '$reinstall You can also click "Install" to download a verified FFmpeg '
          'build from the official yt-dlp/FFmpeg-Builds release (GPL).';
    }
    return reinstall;
  }

  /// Installs or updates [kind] into [managedBinDir].
  Future<DependencyStatus> install(DependencyKind kind, {InstallProgress? onProgress}) async {
    if (!canInstall(kind)) {
      throw AppError(AppErrorKind.missingDependency, guidance(kind));
    }
    if (_isAndroid) {
      onProgress?.call(null, 'Updating yt-dlp');
      final r = await android!.updateYtDlp();
      _log.info('embedded yt-dlp update: $r');
      final status = await resolve(kind);
      if (!status.isReady) {
        throw AppError(AppErrorKind.missingDependency, 'yt-dlp failed after updating: ${status.message}');
      }
      return status;
    }
    await Directory(managedBinDir).create(recursive: true);
    if (kind == DependencyKind.ytDlp) {
      await _installYtDlpOnedir(onProgress);
    } else {
      await _installFfmpegBuild(onProgress);
    }
    final status = await validate(kind, managedPath(kind), DependencySource.managed);
    if (!status.isReady) {
      throw AppError(
        AppErrorKind.missingDependency,
        'The installed ${kind.label} failed validation: ${status.message}',
      );
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

  /// Installs FFmpeg from yt-dlp/FFmpeg-Builds (Windows zip / Linux tar.xz).
  Future<void> _installFfmpegBuild(InstallProgress? onProgress) async {
    final arm = platform.arch == HostArch.arm64;
    final asset = platform.isLinux
        ? (arm ? DependencySources.ffmpegLinuxArm64Asset : DependencySources.ffmpegLinuxX64Asset)
        : (arm ? DependencySources.ffmpegWindowsArm64Asset : DependencySources.ffmpegWindowsX64Asset);
    final exe = platform.exeSuffix;
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
      if (asset.endsWith('.tar.xz')) {
        await BinaryInstaller.extractTarXz(archive, extracted);
      } else {
        await BinaryInstaller.extractZip(archive, extracted);
      }
      final files = await extracted.list(recursive: true).where((e) => e is File).cast<File>().toList();
      File? find(String name) => files.where((f) => p.basename(f.path).toLowerCase() == name).firstOrNull;
      final ffmpeg = find('ffmpeg$exe');
      final ffprobe = find('ffprobe$exe');
      if (ffmpeg == null || ffprobe == null) {
        throw const AppError(AppErrorKind.unknown, 'The FFmpeg archive didn\'t contain ffmpeg and ffprobe.');
      }
      for (final (src, name) in [(ffmpeg, 'ffmpeg$exe'), (ffprobe, 'ffprobe$exe')]) {
        final dest = p.join(managedBinDir, name);
        await src.copy(dest);
        await _makeExecutable(dest);
      }
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
      throw AppError(
        AppErrorKind.permission,
        'Couldn\'t mark the downloaded file as executable.',
        detail: '${r.stderr}',
      );
    }
  }

  /// yt-dlp shipped with or updated by Finder can be updated in place (sites
  /// change often, so a newer yt-dlp is sometimes needed between releases).
  /// The update goes to the app data folder and takes precedence over the
  /// bundled copy. Custom paths must be updated by whatever installed them.
  bool canUpdate(DependencyStatus status) =>
      status.isReady &&
      (status.source == DependencySource.managed || status.source == DependencySource.bundled) &&
      canInstall(status.kind);
}
