import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../core/config/app_config.dart';
import '../process_service.dart';

final _log = Logger('android');

/// On Android, yt-dlp (with its own Python runtime) and FFmpeg ship inside the
/// APK as native libraries (youtubedl-android). They can't be started with
/// `Process.start`, so the Kotlin side runs them and streams output back.
///
/// These sentinel "paths" stand in for executables everywhere the desktop code
/// expects a path.
abstract final class AndroidBundled {
  static const ytDlpPath = 'bundled://yt-dlp';
  static const ffmpegPath = 'bundled://ffmpeg';

  static bool isBundled(String? path) => path != null && path.startsWith('bundled://');
}

/// Thin wrapper over the `finder/toolchain` platform channels.
class AndroidToolchain {
  AndroidToolchain({
    this._method = const MethodChannel('finder/toolchain'),
    EventChannel events = const EventChannel('finder/toolchain/events'),
  }) : _eventsChannel = events;

  final MethodChannel _method;
  final EventChannel _eventsChannel;
  Stream<Map<Object?, Object?>>? _events;

  /// All toolchain events: `{id, type: 'out', line}`,
  /// `{id, type: 'exit', code, stderr}` and `{type: 'cancelAll'}` (the user
  /// tapped "Cancel all" on the background-download notification).
  Stream<Map<Object?, Object?>> get events =>
      _events ??= _eventsChannel.receiveBroadcastStream().map((e) => e as Map<Object?, Object?>).asBroadcastStream();

  Future<void> start(int id, List<String> args) => _method.invokeMethod<void>('start', {'id': id, 'args': args});

  Future<void> stop(int id) => _method.invokeMethod<void>('stop', {'id': id});

  /// Waits until the yt-dlp / FFmpeg payloads unpacked from the APK are ready.
  /// Call during startup (first launch can take several seconds).
  Future<void> ensureReady() => _method.invokeMethod<void>('ensureReady');

  Future<String?> ffmpegVersion() => _method.invokeMethod<String>('ffmpegVersion');

  /// Updates the embedded yt-dlp to the latest stable release.
  /// Returns `done` or `alreadyUpToDate`.
  Future<String?> updateYtDlp() => _method.invokeMethod<String>('updateYtDlp');

  /// Public `Download/Finder` folder.
  Future<String?> downloadsDirectory() => _method.invokeMethod<String>('downloadsDirectory');

  /// Requests legacy storage permission where needed (Android 9 and older).
  Future<bool> ensureStoragePermission() async => await _method.invokeMethod<bool>('ensureStoragePermission') ?? false;

  /// Android 13+: asks (once per launch) to post notifications, which show
  /// background download progress. Downloads work either way.
  Future<bool> ensureNotificationPermission() async =>
      await _method.invokeMethod<bool>('ensureNotificationPermission') ?? false;

  /// Reports the queue to the foreground service that keeps downloads running
  /// in the background (and drives its progress notification). The service
  /// runs while [active] + [queued] > 0 and stops shortly after.
  Future<void> setForegroundStatus({
    required int active,
    required int queued,
    String? title,
    double? progress,
    int completed = 0,
    int total = 0,
  }) => _method.invokeMethod<void>('setForegroundStatus', {
    'active': active,
    'queued': queued,
    'title': title,
    'progress': progress,
    'completed': completed,
    'total': total,
  });

  Future<void> openFile(String path) => _method.invokeMethod<void>('openFile', {'path': path});

  Future<void> openFolder(String path) => _method.invokeMethod<void>('openFolder', {'path': path});
}

/// [ProcessService] for Android: runs the embedded yt-dlp through the channel.
///
/// Only the bundled yt-dlp can be "started"; arguments are passed as a list and
/// never through a shell, exactly as on desktop.
class AndroidProcessService extends ProcessService {
  AndroidProcessService(this._toolchain);

  final AndroidToolchain _toolchain;
  final Map<int, _ChannelProcess> _live = {};
  StreamSubscription<Map<Object?, Object?>>? _sub;
  int _nextId = 1;

  @override
  int get liveCount => _live.length;

  void _ensureListening() {
    _sub ??= _toolchain.events.listen((e) {
      final id = e['id'] as int?;
      final proc = id == null ? null : _live[id];
      if (proc == null) return;
      switch (e['type']) {
        case 'out':
          proc._stdout.add(e['line'] as String? ?? '');
        case 'exit':
          _live.remove(id);
          proc._finish(e['code'] as int? ?? 1, e['stderr'] as String? ?? '');
      }
    }, onError: (Object e) => _log.warning('toolchain event stream failed', e));
  }

  @override
  Future<ManagedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (executable != AndroidBundled.ytDlpPath) {
      throw ProcessException(executable, arguments, 'Only the bundled yt-dlp can run on Android');
    }
    _ensureListening();
    final id = _nextId++;
    final proc = _ChannelProcess(id, _toolchain);
    _live[id] = proc;
    try {
      await _toolchain.start(id, arguments);
    } on PlatformException catch (e) {
      _live.remove(id);
      throw ProcessException(executable, arguments, e.message ?? e.code);
    }
    return proc;
  }

  @override
  Future<void> killAll({Duration grace = const Duration(seconds: 2)}) async {
    final procs = _live.values.toList();
    await Future.wait(procs.map((p) => p.terminate(grace: grace)));
  }
}

class _ChannelProcess implements ManagedProcess {
  _ChannelProcess(this.pid, this._toolchain);

  @override
  final int pid;
  final AndroidToolchain _toolchain;
  // Single-subscription controllers buffer output that arrives before the
  // caller starts listening.
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  @override
  late final Stream<String> stdoutLines = _stdout.stream.asBroadcastStream();
  @override
  late final Stream<String> stderrLines = _stderr.stream.asBroadcastStream();
  final _exit = Completer<int>();
  bool _terminating = false;

  void _finish(int code, String stderr) {
    // yt-dlp's stderr is only available once the process ends.
    for (final line in stderr.split(RegExp(r'\r?\n'))) {
      if (line.isNotEmpty) _stderr.add(line);
    }
    _stdout.close();
    _stderr.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get isTerminating => _terminating;

  @override
  Future<void> terminate({Duration grace = AppConfig.processKillGrace}) async {
    _terminating = true;
    try {
      await _toolchain.stop(pid);
    } catch (e) {
      _log.info('stop failed for $pid: $e');
    }
    await exitCode.timeout(grace * 2, onTimeout: () => -1);
  }
}
