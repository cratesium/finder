import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../core/config/app_config.dart';
import '../process_service.dart';

final _log = Logger('android');

/// Sentinel paths used where desktop code expects yt-dlp / ffmpeg executables.
abstract final class AndroidBundled {
  static const ytDlpPath = 'bundled://yt-dlp';
  static const ffmpegPath = 'bundled://ffmpeg';

  static bool isBundled(String? path) => path != null && path.startsWith('bundled://');
}

/// Platform channel to the Kotlin [Toolchain] (youtubedl-android).
class AndroidToolchain {
  AndroidToolchain({
    this._method = const MethodChannel('finder/toolchain'),
    EventChannel events = const EventChannel('finder/toolchain/events'),
  }) : _eventsChannel = events;

  final MethodChannel _method;
  final EventChannel _eventsChannel;
  Stream<Map<Object?, Object?>>? _events;

  Stream<Map<Object?, Object?>> get events =>
      _events ??= _eventsChannel.receiveBroadcastStream().map((e) => e as Map<Object?, Object?>).asBroadcastStream();

  Future<void> start(int id, List<String> args) => _method.invokeMethod<void>('start', {'id': id, 'args': args});

  Future<void> stop(int id) => _method.invokeMethod<void>('stop', {'id': id});

  /// First launch unpacks Python / yt-dlp from the APK; can take a few seconds.
  Future<void> ensureReady() => _method.invokeMethod<void>('ensureReady');

  Future<String?> updateYtDlp() => _method.invokeMethod<String>('updateYtDlp');

  Future<String?> downloadsDirectory() => _method.invokeMethod<String>('downloadsDirectory');

  Future<bool> ensureStoragePermission() async => await _method.invokeMethod<bool>('ensureStoragePermission') ?? false;

  Future<void> openFile(String path) => _method.invokeMethod<void>('openFile', {'path': path});

  Future<void> openFolder(String path) => _method.invokeMethod<void>('openFolder', {'path': path});
}

/// Runs embedded yt-dlp via the platform channel (no [Process.start] on Android).
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
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  @override
  late final Stream<String> stdoutLines = _stdout.stream.asBroadcastStream();
  @override
  late final Stream<String> stderrLines = _stderr.stream.asBroadcastStream();
  final _exit = Completer<int>();
  bool _terminating = false;

  void _finish(int code, String stderr) {
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