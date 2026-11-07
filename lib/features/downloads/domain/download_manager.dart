import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../../core/errors/app_error.dart';
import '../../../core/utils/path_utils.dart';
import '../../../models/download_options.dart';
import '../../../models/download_task.dart';
import '../../../models/history_record.dart';
import '../../../services/downloader_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/trust_store_service.dart';
import '../../../services/ytdlp/ytdlp_args.dart';
import '../../../services/ytdlp/ytdlp_output_parser.dart';
import '../../history/data/history_repository.dart';

final _log = Logger('manager');

/// Paths to the tools at the moment a task starts.
class ResolvedTools {
  const ResolvedTools({this.ytDlpPath, this.ffmpegPath, this.network = YtDlpNetworkConfig.none});
  final String? ytDlpPath;
  final String? ffmpegPath;
  final YtDlpNetworkConfig network;
}

typedef ToolResolver = Future<ResolvedTools> Function();
typedef DirectoryCheck = Future<bool> Function(String dir);
typedef FileSizeReader = Future<int?> Function(String path);

/// Reads the real resolution of a finished file (via ffprobe) when yt-dlp
/// couldn't report it.
typedef ResolutionProbe = Future<int?> Function(String ffmpegPath, String file);

class EnqueueResult {
  const EnqueueResult({
    this.added = 0,
    this.duplicates = 0,
    this.skippedCompleted = 0,
    this.unavailable = 0,
  });

  final int added;
  final int duplicates;
  final int skippedCompleted;
  final int unavailable;

  String describe() {
    final parts = <String>[
      if (added > 0) '$added added to the queue',
      if (skippedCompleted > 0) '$skippedCompleted already downloaded',
      if (duplicates > 0) '$duplicates already queued',
      if (unavailable > 0) '$unavailable unavailable',
    ];
    return parts.isEmpty ? 'Nothing to download.' : '${parts.join(', ')}.';
  }
}

enum _StopReason { pause, cancel, shutdown }

class _Run {
  DownloadJob? job;
  _StopReason? stopReason;
  String? lastFormatId;
  int streamIndex = 1;
}

/// Owns the download queue: scheduling, concurrency, progress, persistence.
///
/// Independent from Flutter so it can be tested and reused.
class DownloadManager {
  DownloadManager({
    required this._downloader,
    required this._history,
    required this._tools,
    this._notifications = const NoopNotificationService(),
    DirectoryCheck? directoryCheck,
    FileSizeReader? fileSize,
    this._resolutionProbe,
    int maxConcurrent = 2,
    this.skipCompleted = true,
    this.notificationsEnabled = true,
    this.progressThrottle = const Duration(milliseconds: 150),
    DateTime Function()? clock,
  })  : _directoryCheck = directoryCheck ?? PathUtils.ensureWritableDirectory,
        _fileSize = fileSize ?? _defaultFileSize,
        _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent,
        _clock = clock ?? DateTime.now;

  final DownloaderService _downloader;
  final HistoryRepository _history;
  final ToolResolver _tools;
  final NotificationService _notifications;
  final DirectoryCheck _directoryCheck;
  final FileSizeReader _fileSize;
  final ResolutionProbe? _resolutionProbe;
  final DateTime Function() _clock;
  final Duration progressThrottle;

  bool skipCompleted;
  bool notificationsEnabled;

  final List<DownloadTask> _tasks = [];
  final Map<String, _Run> _runs = {};
  final Map<String, Set<String>> _partials = {};
  final _changes = StreamController<List<DownloadTask>>.broadcast();
  Timer? _emitTimer;
  int _idCounter = 0;
  int _maxConcurrent;
  bool _queuePaused = false;
  bool _disposed = false;

  static Future<int?> _defaultFileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  Stream<List<DownloadTask>> get changes => _changes.stream;
  int get maxConcurrent => _maxConcurrent;
  bool get queuePaused => _queuePaused;
  int get activeCount => _tasks.where((t) => t.status.isActive).length;
  int get waitingCount => _tasks.where((t) => t.status == TaskStatus.queued).length;

  DownloadTask? taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  set maxConcurrent(int value) {
    _maxConcurrent = value < 1 ? 1 : value;
    _pump();
  }

  set queuePaused(bool value) {
    _queuePaused = value;
    _emitNow();
    _pump();
  }

  // ---------------------------------------------------------------------------
  // Queue operations
  // ---------------------------------------------------------------------------

  Future<EnqueueResult> enqueue(List<DownloadRequest> requests) async {
    var added = 0, dup = 0, skipped = 0, unavailable = 0;
    for (final r in requests) {
      if (!r.entry.availability.isDownloadable || r.entry.url.isEmpty) {
        unavailable++;
        continue;
      }
      final key = r.dedupeKey;
      final active = _tasks.any((t) => t.request.dedupeKey == key && t.status.blocksDuplicates);
      if (active) {
        dup++;
        continue;
      }
      // Replace finished tasks for the same item instead of listing it twice.
      _tasks.removeWhere((t) => t.request.dedupeKey == key && t.status.isTerminal);

      if (skipCompleted) {
        final existing = await _safeFind(key);
        final path = existing?.filePath;
        if (existing?.status == HistoryStatus.completed &&
            path != null &&
            await File(path).exists()) {
          _tasks.add(DownloadTask(
            id: _newId(),
            request: r,
            status: TaskStatus.skipped,
            createdAt: _clock(),
            finishedAt: _clock(),
            filePath: path,
            fileSize: existing!.fileSize,
            notice: 'Already downloaded — skipped.',
          ));
          skipped++;
          continue;
        }
      }
      _tasks.add(DownloadTask(
        id: _newId(),
        request: r,
        status: TaskStatus.queued,
        createdAt: _clock(),
      ));
      added++;
    }
    _log.info('enqueue: added=$added dup=$dup skipped=$skipped unavailable=$unavailable');
    _emitNow();
    _pump();
    return EnqueueResult(
      added: added,
      duplicates: dup,
      skippedCompleted: skipped,
      unavailable: unavailable,
    );
  }

  Future<HistoryRecord?> _safeFind(String key) async {
    try {
      return await _history.findByDedupeKey(key);
    } catch (e) {
      _log.warning('history lookup failed', e);
      return null;
    }
  }

  Future<void> pause(String id) async {
    final t = taskById(id);
    if (t == null) return;
    if (t.status == TaskStatus.queued) {
      _update(id, (t) => t.copyWith(status: TaskStatus.paused));
      return;
    }
    if (!t.status.isActive) return;
    final run = _runs[id];
    if (run == null) return;
    run.stopReason = _StopReason.pause;
    _update(id, (t) => t.copyWith(
        status: TaskStatus.paused,
        progress: DownloadProgress(
          downloadedBytes: t.progress.downloadedBytes,
          totalBytes: t.progress.totalBytes,
          totalBytesIsEstimate: t.progress.totalBytesIsEstimate,
          streamIndex: t.progress.streamIndex,
          phaseLabel: 'Paused — partial data kept',
        )));
    await run.job?.stop();
  }

  void resume(String id) {
    final t = taskById(id);
    if (t == null || t.status != TaskStatus.paused) return;
    _update(id, (t) => t.copyWith(status: TaskStatus.queued));
    _pump();
  }

  Future<void> cancel(String id) async {
    final t = taskById(id);
    if (t == null || t.status.isTerminal) return;
    final run = _runs[id];
    if (run != null) {
      run.stopReason = _StopReason.cancel;
      _update(id, (t) => t.copyWith(
          status: TaskStatus.cancelled,
          finishedAt: _clock(),
          progress: const DownloadProgress(phaseLabel: 'Cancelling…')));
      await run.job?.stop();
    } else {
      _update(id, (t) => t.copyWith(status: TaskStatus.cancelled, finishedAt: _clock()));
      await _cleanupPartials(id);
      await _recordHistory(taskById(id)!, HistoryStatus.cancelled);
    }
  }

  void retry(String id) {
    final t = taskById(id);
    if (t == null || !(t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)) return;
    _update(
      id,
      (t) => t.copyWith(
        status: TaskStatus.queued,
        clearError: true,
        clearNotice: true,
        clearFinishedAt: true,
        progress: const DownloadProgress(),
      ),
    );
    _pump();
  }

  /// Queues a fresh task for a [request] (used by History → "Download again").
  Future<EnqueueResult> requeue(DownloadRequest request) => enqueue([request]);

  Future<void> remove(String id) async {
    final t = taskById(id);
    if (t == null) return;
    if (t.status.isActive) await cancel(id);
    _tasks.removeWhere((x) => x.id == id);
    _emitNow();
  }

  void clearFinished() {
    _tasks.removeWhere((t) =>
        t.status == TaskStatus.completed ||
        t.status == TaskStatus.skipped ||
        t.status == TaskStatus.cancelled);
    _emitNow();
  }

  /// Moves a waiting task by [delta] positions among waiting tasks.
  void move(String id, int delta) {
    final waiting = _tasks
        .where((t) =>
            (t.status == TaskStatus.queued || t.status == TaskStatus.paused) &&
            !_runs.containsKey(t.id))
        .toList();
    final idx = waiting.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final target = (idx + delta).clamp(0, waiting.length - 1);
    if (target == idx) return;
    final task = waiting[idx];
    final anchor = waiting[target];
    _tasks.remove(task);
    final anchorIdx = _tasks.indexOf(anchor);
    _tasks.insert(delta > 0 ? anchorIdx + 1 : anchorIdx, task);
    _emitNow();
  }

  void moveToTop(String id) => move(id, -1 << 20);

  /// Position (1-based) of a waiting task, or null.
  int? queuePosition(String id) {
    var pos = 0;
    for (final t in _tasks) {
      if (t.status == TaskStatus.queued) {
        pos++;
        if (t.id == id) return pos;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _pump() {
    if (_disposed || _queuePaused) return;
    var running = _runs.length;
    for (final t in List.of(_tasks)) {
      if (running >= _maxConcurrent) break;
      // A previous run may still be shutting down (e.g. resumed while pausing).
      if (t.status != TaskStatus.queued || _runs.containsKey(t.id)) continue;
      running++;
      unawaited(_execute(t.id));
    }
  }

  Future<void> _execute(String id) async {
    final run = _Run();
    _runs[id] = run;
    _update(
      id,
      (t) => t.copyWith(
        status: TaskStatus.preparing,
        attempts: t.attempts + 1,
        startedAt: _clock(),
        clearError: true,
        clearNotice: true,
        progress: const DownloadProgress(phaseLabel: 'Starting yt-dlp'),
      ),
    );
    try {
      final task = taskById(id)!;
      final tools = await _tools();
      final ytDlp = tools.ytDlpPath;
      if (ytDlp == null) {
        throw const AppError(AppErrorKind.missingDependency,
            'yt-dlp isn\'t installed. Open Settings → Dependencies to install it.');
      }
      if (task.options.requiresFfmpeg && tools.ffmpegPath == null) {
        throw AppError(
          AppErrorKind.missingDependency,
          task.options.isAudioOnly
              ? 'FFmpeg is required to extract audio. Set it up in Settings → Dependencies.'
              : 'FFmpeg is required to merge video and audio. Set it up in Settings → Dependencies.',
        );
      }
      final dir = task.request.effectiveDirectory;
      if (!await _directoryCheck(dir)) {
        throw AppError(AppErrorKind.permission,
            'CourseGrab can\'t write to the destination folder. Choose another folder or check its permissions.',
            detail: PathUtils.displayPath(dir));
      }
      await _recordHistory(task, HistoryStatus.downloading);
      if (run.stopReason != null) return await _handleStopped(id, run);

      final spec = DownloadJobSpec(
        url: task.entry.url,
        options: task.options,
        directory: dir,
        outputTemplate: YtDlpArgs.outputTemplate(
          playlistIndex: task.entry.playlistIndex,
          numbered: task.options.numberPlaylistItems && task.request.playlistTitle != null,
        ),
        ytDlpPath: ytDlp,
        ffmpegPath: tools.ffmpegPath,
        network: tools.network,
      );
      final job = await _downloader.start(spec);
      run.job = job;
      if (run.stopReason != null) await job.stop();

      final sub = job.events.listen((e) => _onEvent(id, run, e));
      final outcome = await job.outcome;
      await sub.cancel();
      _partials.putIfAbsent(id, () => {}).addAll(job.announcedDestinations);

      switch (outcome) {
        case DownloadSucceeded():
          await _handleSuccess(id, outcome, ffmpegPath: tools.ffmpegPath);
        case DownloadFailed(:final error):
          if (run.stopReason != null) {
            await _handleStopped(id, run);
          } else {
            await _handleFailure(id, error);
          }
        case DownloadStopped():
          await _handleStopped(id, run);
      }
    } on AppError catch (e) {
      if (run.stopReason != null) {
        await _handleStopped(id, run);
      } else {
        await _handleFailure(id, e);
      }
    } catch (e, st) {
      _log.severe('unexpected error running task', e, st);
      await _handleFailure(id, AppError.of(AppErrorKind.unknown, detail: '$e'));
    } finally {
      if (identical(_runs[id], run)) _runs.remove(id);
      _emitNow();
      _pump();
    }
  }

  void _onEvent(String id, _Run run, YtDlpEvent e) {
    final t = taskById(id);
    if (t == null || run.stopReason != null) return;
    switch (e) {
      case ProgressEvent():
        final fid = e.formatId;
        if (fid != null && run.lastFormatId != null && fid != run.lastFormatId) {
          run.streamIndex++;
        }
        if (fid != null) run.lastFormatId = fid;
        final total = e.totalBytes ?? e.totalBytesEstimate;
        final progress = DownloadProgress(
          downloadedBytes: e.downloadedBytes,
          totalBytes: total,
          totalBytesIsEstimate: e.totalBytes == null && e.totalBytesEstimate != null,
          speed: e.speed,
          etaSeconds: e.eta,
          streamIndex: run.streamIndex,
          fragmentIndex: e.fragmentIndex,
          fragmentCount: e.fragmentCount,
          phaseLabel: _streamLabel(t.options, run.streamIndex, e.status),
        );
        final statusChanged = t.status != TaskStatus.downloading;
        _replace(t.copyWith(status: TaskStatus.downloading, progress: progress));
        statusChanged ? _emitNow() : _emitThrottled();
      case PostProcessEvent(:final status):
        if (status == 'started' || status == 'processing') {
          _replace(t.copyWith(
            status: TaskStatus.processing,
            progress: DownloadProgress(
              downloadedBytes: t.progress.downloadedBytes,
              totalBytes: t.progress.totalBytes,
              streamIndex: t.progress.streamIndex,
              phaseLabel: e.label,
            ),
          ));
          _emitNow();
        }
      default:
        break;
    }
  }

  static String _streamLabel(DownloadOptions o, int stream, String status) {
    if (status == 'finished') return 'Stream $stream downloaded';
    if (o.isAudioOnly) return 'Downloading audio';
    return stream == 1 ? 'Downloading stream 1 (video)' : 'Downloading stream $stream (audio)';
  }

  Future<void> _handleSuccess(String id, DownloadSucceeded outcome, {String? ffmpegPath}) async {
    final t = taskById(id);
    if (t == null) return;
    final size = await _fileSize(outcome.filePath);
    String? notice;
    final requested = t.options.quality.height;
    var actual = outcome.resolution;
    if (actual == null && !t.options.isAudioOnly && ffmpegPath != null && _resolutionProbe != null) {
      try {
        actual = await _resolutionProbe(ffmpegPath, outcome.filePath);
      } catch (e) {
        _log.fine('resolution probe failed: $e');
      }
    }
    if (!t.options.isAudioOnly && requested != null && actual != null && actual < requested * 0.95) {
      notice = '${t.options.quality.label} wasn\'t available — downloaded ${actual}p instead.';
    }
    final done = t.copyWith(
      status: TaskStatus.completed,
      finishedAt: _clock(),
      filePath: outcome.filePath,
      fileSize: size,
      actualResolution: actual,
      actualExtension: outcome.extension,
      notice: notice,
      progress: DownloadProgress(
        downloadedBytes: size,
        totalBytes: size,
        streamIndex: t.progress.streamIndex,
        phaseLabel: 'Completed',
      ),
    );
    _replace(done);
    _partials.remove(id);
    await _recordHistory(done, HistoryStatus.completed);
    _notify('Download complete', done.title);
  }

  Future<void> _handleFailure(String id, AppError error) async {
    final t = taskById(id);
    if (t == null) return;
    _log.warning('task failed: ${error.kind.name} ${error.detail ?? ''}');
    final failed = t.copyWith(
      status: TaskStatus.failed,
      error: error,
      finishedAt: _clock(),
      progress: DownloadProgress(
        downloadedBytes: t.progress.downloadedBytes,
        totalBytes: t.progress.totalBytes,
        streamIndex: t.progress.streamIndex,
        phaseLabel: error.title,
      ),
    );
    _replace(failed);
    await _recordHistory(failed, HistoryStatus.failed, error: error.message);
    _notify('Download failed', '${t.title}: ${error.message}');
  }

  Future<void> _handleStopped(String id, _Run run) async {
    final t = taskById(id);
    if (t == null) return;
    switch (run.stopReason) {
      case _StopReason.pause:
        // The user may have resumed or cancelled while the process was stopping.
        if (t.status == TaskStatus.paused) {
          _replace(t.copyWith(status: TaskStatus.paused));
        }
      case _StopReason.cancel:
        _replace(t.copyWith(status: TaskStatus.cancelled, finishedAt: _clock(),
            progress: const DownloadProgress(phaseLabel: 'Cancelled')));
        await _cleanupPartials(id);
        await _recordHistory(taskById(id)!, HistoryStatus.cancelled);
      case _StopReason.shutdown:
        await _recordHistory(t, HistoryStatus.interrupted,
            error: 'CourseGrab was closed before this download finished.');
      case null:
        break;
    }
  }

  /// Deletes yt-dlp's intermediate files for a cancelled task.
  ///
  /// Only files sharing the announced output stem *and* carrying a temporary
  /// suffix are removed, so finished media is never touched.
  Future<void> _cleanupPartials(String id) async {
    final dests = _partials.remove(id);
    if (dests == null || dests.isEmpty) return;
    for (final dest in dests) {
      final dir = Directory(p.dirname(dest));
      if (!await dir.exists()) continue;
      final stem = p.basenameWithoutExtension(dest);
      try {
        await for (final f in dir.list(followLinks: false)) {
          if (f is! File) continue;
          final name = p.basename(f.path);
          if (isTemporaryArtifact(name, stem)) {
            await f.delete();
            _log.fine('removed partial file');
          }
        }
      } catch (e) {
        _log.info('partial cleanup failed: $e');
      }
    }
  }

  static final _formatPart = RegExp(r'\.f[0-9A-Za-z_-]+\.[A-Za-z0-9]+$');

  /// Whether [name] is a temporary file produced while downloading [stem].
  static bool isTemporaryArtifact(String name, String stem) {
    if (!name.startsWith('$stem.')) return false;
    final rest = name.substring(stem.length);
    return rest.endsWith('.part') ||
        rest.endsWith('.ytdl') ||
        rest.contains('.part-Frag') ||
        rest.startsWith('.temp.') ||
        _formatPart.hasMatch(rest);
  }

  Future<void> _recordHistory(DownloadTask t, HistoryStatus status, {String? error}) async {
    final res = t.actualResolution;
    final record = HistoryRecord(
      dedupeKey: t.request.dedupeKey,
      videoId: t.entry.id,
      extractor: t.entry.extractor,
      title: t.title,
      url: t.entry.url,
      playlistTitle: t.request.playlistTitle,
      playlistIndex: t.entry.playlistIndex,
      thumbnailUrl: t.entry.thumbnailUrl,
      createdAt: t.createdAt,
      completedAt: status == HistoryStatus.completed ? (t.finishedAt ?? _clock()) : null,
      resolution: t.options.isAudioOnly ? 'Audio' : (res != null ? '${res}p' : null),
      format: t.actualExtension ?? (t.filePath != null ? p.extension(t.filePath!).replaceFirst('.', '') : null),
      fileSize: t.fileSize,
      filePath: t.filePath,
      destinationDir: t.request.effectiveDirectory,
      status: status,
      errorMessage: error,
      options: t.options,
    );
    try {
      await _history.upsert(record);
    } catch (e) {
      // History persistence must not break the download itself.
      _log.severe('failed to persist history', e);
    }
  }

  void _notify(String title, String body) {
    if (!notificationsEnabled) return;
    unawaited(_notifications.show(title: title, body: body));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Stops all running processes. Called when the application exits.
  Future<void> shutdown() async {
    if (_disposed) return;
    _queuePaused = true;
    final runs = Map.of(_runs);
    _log.info('shutdown: stopping ${runs.length} active download(s)');
    await Future.wait(runs.entries.map((e) async {
      e.value.stopReason = _StopReason.shutdown;
      await e.value.job?.stop();
    }));
    for (final id in runs.keys) {
      final t = taskById(id);
      if (t != null) {
        await _recordHistory(t, HistoryStatus.interrupted,
            error: 'CourseGrab was closed before this download finished.');
      }
    }
    _disposed = true;
    _emitTimer?.cancel();
    await _changes.close();
  }

  // ---------------------------------------------------------------------------
  // State helpers
  // ---------------------------------------------------------------------------

  String _newId() => 't${_clock().microsecondsSinceEpoch}-${_idCounter++}';

  void _replace(DownloadTask t) {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) _tasks[i] = t;
  }

  void _update(String id, DownloadTask Function(DownloadTask) f) {
    final i = _tasks.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _tasks[i] = f(_tasks[i]);
    _emitNow();
  }

  void _emitNow() {
    _emitTimer?.cancel();
    _emitTimer = null;
    if (!_changes.isClosed) _changes.add(tasks);
  }

  void _emitThrottled() {
    if (_emitTimer != null) return;
    _emitTimer = Timer(progressThrottle, () {
      _emitTimer = null;
      if (!_changes.isClosed) _changes.add(tasks);
    });
  }
}
