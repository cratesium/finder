import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/di/providers.dart';
import '../../features/downloads/application/download_providers.dart';
import '../../models/download_task.dart';
import 'android_toolchain.dart';

final _log = Logger('android.background');

/// Snapshot of the queue shown in the background-download notification.
class ForegroundStatus {
  const ForegroundStatus({
    required this.active,
    required this.queued,
    this.title,
    this.progress,
    this.completed = 0,
    this.total = 0,
  });

  /// Summarizes [tasks]. Paused tasks don't keep the service alive: they
  /// can't make progress without the user.
  factory ForegroundStatus.of(List<DownloadTask> tasks) {
    final active = tasks.where((t) => t.status.isActive).toList();
    final queued = tasks.where((t) => t.status == TaskStatus.queued).length;
    final fractions = active.map((t) => t.progress.fraction).whereType<double>().toList();
    final current = active.where((t) => t.status == TaskStatus.downloading).firstOrNull ?? active.firstOrNull;
    // "N of M" counts the tasks of this session that are done or still pending.
    final finished = tasks.where((t) => t.status == TaskStatus.completed || t.status == TaskStatus.skipped).length;
    return ForegroundStatus(
      active: active.length,
      queued: queued,
      title: current?.title,
      progress: active.isEmpty || fractions.length != active.length
          ? null
          : fractions.reduce((a, b) => a + b) / fractions.length,
      completed: finished,
      total: finished + active.length + queued,
    );
  }

  final int active;
  final int queued;
  final String? title;
  final double? progress;
  final int completed;
  final int total;

  bool get isIdle => active == 0 && queued == 0;

  /// Same notification content, ignoring progress changes under 1 %.
  bool sameAs(ForegroundStatus o) =>
      active == o.active &&
      queued == o.queued &&
      title == o.title &&
      completed == o.completed &&
      total == o.total &&
      (progress == null) == (o.progress == null) &&
      ((progress ?? 0) - (o.progress ?? 0)).abs() < 0.01;
}

/// Mirrors the download queue to Android's foreground service so downloads
/// keep running in the background, and handles the notification's
/// "Cancel all" action.
class AndroidBackgroundSync {
  AndroidBackgroundSync(this._toolchain, {this.minInterval = const Duration(seconds: 1)});

  final AndroidToolchain _toolchain;

  /// Android throttles frequent notification updates; progress-only changes
  /// are sent at most this often. State changes are sent immediately.
  final Duration minInterval;

  ForegroundStatus? _sent;
  ForegroundStatus? _pending;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;
  bool _askedPermission = false;

  void update(List<DownloadTask> tasks) {
    final next = ForegroundStatus.of(tasks);
    final last = _sent;
    if (last != null && next.sameAs(last)) return;
    if (!next.isIdle && !_askedPermission) {
      _askedPermission = true;
      unawaited(_toolchain.ensureNotificationPermission().catchError((Object _) => false));
    }
    final structural = last == null || last.active != next.active || last.queued != next.queued;
    final wait = minInterval - DateTime.now().difference(_lastSent);
    if (structural || wait <= Duration.zero) {
      _send(next);
    } else {
      _pending = next;
      _timer ??= Timer(wait, () {
        _timer = null;
        final p = _pending;
        _pending = null;
        if (p != null) _send(p);
      });
    }
  }

  void _send(ForegroundStatus s) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _sent = s;
    _lastSent = DateTime.now();
    _toolchain
        .setForegroundStatus(
          active: s.active,
          queued: s.queued,
          title: s.title,
          progress: s.progress,
          completed: s.completed,
          total: s.total,
        )
        .catchError((Object e) => _log.info('foreground status not delivered: $e'));
  }

  void dispose() => _timer?.cancel();
}

/// Activates background downloads on Android (no-op elsewhere). Watch it once
/// from the app root: `ref.watch(androidBackgroundSyncProvider);`
final androidBackgroundSyncProvider = Provider<void>((ref) {
  final toolchain = ref.watch(androidToolchainProvider);
  if (toolchain == null) return;
  final sync = AndroidBackgroundSync(toolchain);
  ref.listen<List<DownloadTask>>(tasksProvider, (_, tasks) => sync.update(tasks), fireImmediately: true);
  final sub = toolchain.events.where((e) => e['type'] == 'cancelAll').listen((_) async {
    final manager = ref.read(downloadManagerProvider);
    _log.info('cancel all requested from the notification');
    for (final t in manager.tasks.where((t) => !t.status.isTerminal)) {
      try {
        await manager.cancel(t.id);
      } catch (e) {
        _log.info('cancel failed for a task: $e');
      }
    }
  }, onError: (Object e) => _log.info('toolchain events unavailable: $e'));
  ref.onDispose(() {
    sync.dispose();
    sub.cancel();
  });
});
