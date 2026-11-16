import 'dart:io';

import 'package:logging/logging.dart';

import '../../core/errors/app_error.dart';
import '../../models/dependency_status.dart';
import '../binary_installer.dart';
import '../dependency_manager.dart';
import '../file_opener_service.dart';
import 'ios_bridge.dart';

final _log = Logger('ios');

/// Sentinel "paths" for the built-in iOS engine. Nothing is ever executed at
/// these paths; they only satisfy the shared "tools ready" checks.
abstract final class IosBuiltin {
  static const ytDlpPath = 'builtin://ios/engine';
  static const ffmpegPath = 'builtin://ios/avfoundation';

  static bool isBuiltin(String? path) => path != null && path.startsWith('builtin://');
}

/// iOS has no yt-dlp/FFmpeg: extraction is done in Dart and muxing by
/// AVFoundation. Both "tools" are therefore always ready and never installed,
/// updated or probed.
class IosDependencyManager extends DependencyManager {
  IosDependencyManager({required super.platform, required super.processes, required super.managedBinDir});

  static const _version = 'Built-in';

  DependencyStatus _ready(DependencyKind kind) => DependencyStatus(
    kind: kind,
    state: DependencyState.ready,
    path: kind == DependencyKind.ytDlp ? IosBuiltin.ytDlpPath : IosBuiltin.ffmpegPath,
    version: _version,
    source: DependencySource.bundled,
  );

  @override
  Future<DependencySnapshot> snapshot({String? ytDlpPath, String? ffmpegPath}) async =>
      DependencySnapshot(ytDlp: _ready(DependencyKind.ytDlp), ffmpeg: _ready(DependencyKind.ffmpeg));

  @override
  Future<DependencyStatus> resolve(DependencyKind kind, {String? customPath}) async => _ready(kind);

  @override
  Future<DependencyStatus> validate(DependencyKind kind, String path, DependencySource source) async => _ready(kind);

  @override
  bool canInstall(DependencyKind kind) => false;

  @override
  bool canUpdate(DependencyStatus status) => false;

  @override
  String guidance(DependencyKind kind) =>
      'On iPhone and iPad, Finder uses a built-in download engine and the system\'s '
      'AVFoundation framework. There is nothing to install.';

  @override
  Future<DependencyStatus> install(DependencyKind kind, {InstallProgress? onProgress}) async => _ready(kind);
}

/// Opens downloads with iOS system UI: Quick Look, the share sheet and the
/// Files app (downloads live in "On My iPhone/iPad → Finder").
class IosFileOpener implements FileOpenerService {
  const IosFileOpener([this._bridge = const IosBridge()]);
  final IosBridge _bridge;

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      _log.warning('ios open failed', e);
      throw AppError(AppErrorKind.unknown, 'iOS couldn\'t open that item.', detail: '$e');
    }
  }

  Future<void> _requireFile(String path) async {
    if (!await File(path).exists()) {
      throw const AppError(AppErrorKind.unavailable, 'That file no longer exists. It may have been moved or deleted.');
    }
  }

  @override
  Future<void> openFile(String path) async {
    await _requireFile(path);
    await _guard(() => _bridge.preview(path));
  }

  /// Opens the Files app at the file's folder; falls back to the share sheet.
  @override
  Future<void> revealInFolder(String path) async {
    await _requireFile(path);
    await _guard(() async {
      if (!await _bridge.openInFiles(File(path).parent.path)) await _bridge.share(path);
    });
  }

  @override
  Future<void> openFolder(String path) => _guard(() async {
    if (!await _bridge.openInFiles(path)) {
      throw const AppError(AppErrorKind.unknown, 'The Files app couldn\'t be opened.');
    }
  });
}
