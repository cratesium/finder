import 'package:path/path.dart' as p;

import '../core/errors/app_error.dart';
import '../core/utils/path_utils.dart';
import 'download_options.dart';
import 'media_info.dart';

enum TaskStatus {
  queued('Queued'),
  preparing('Preparing'),
  downloading('Downloading'),
  processing('Processing'),
  paused('Paused'),
  completed('Completed'),
  skipped('Skipped'),
  failed('Failed'),
  cancelled('Cancelled');

  const TaskStatus(this.label);
  final String label;

  bool get isActive =>
      this == preparing || this == downloading || this == processing;
  bool get isWaiting => this == queued;
  bool get isTerminal =>
      this == completed || this == skipped || this == failed || this == cancelled;

  /// Tasks in these states block an identical new task from being created.
  bool get blocksDuplicates => !isTerminal;
}

/// What the user asked to download.
class DownloadRequest {
  const DownloadRequest({
    required this.entry,
    required this.options,
    this.playlistTitle,
  });

  final MediaEntry entry;
  final DownloadOptions options;
  final String? playlistTitle;

  /// Destination directory including the playlist sub-folder.
  String get effectiveDirectory {
    final base = options.destinationDir;
    final pl = playlistTitle;
    if (pl == null || pl.trim().isEmpty) return base;
    return p.join(base, PathUtils.sanitizeSegment(pl));
  }

  /// Stable deduplication key: same video + same output type + same folder.
  String get dedupeKey =>
      '${entry.stableId}|${options.outputKind}|${PathUtils.normalizeDir(effectiveDirectory)}';
}

/// Live progress reported by yt-dlp. Values are never estimated by CourseGrab.
class DownloadProgress {
  const DownloadProgress({
    this.downloadedBytes,
    this.totalBytes,
    this.totalBytesIsEstimate = false,
    this.speed,
    this.etaSeconds,
    this.streamIndex = 1,
    this.phaseLabel,
    this.fragmentIndex,
    this.fragmentCount,
  });

  final int? downloadedBytes;
  final int? totalBytes;
  final bool totalBytesIsEstimate;
  final double? speed;
  final int? etaSeconds;

  /// 1-based index of the stream currently downloading (video, then audio).
  final int streamIndex;
  final String? phaseLabel;
  final int? fragmentIndex;
  final int? fragmentCount;

  /// Fraction 0..1 of the current stream, or null when the total is unknown.
  double? get fraction {
    final d = downloadedBytes, t = totalBytes;
    if (d != null && t != null && t > 0) return (d / t).clamp(0.0, 1.0);
    final fi = fragmentIndex, fc = fragmentCount;
    if (fi != null && fc != null && fc > 0) return (fi / fc).clamp(0.0, 1.0);
    return null;
  }
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.request,
    required this.status,
    required this.createdAt,
    this.progress = const DownloadProgress(),
    this.error,
    this.filePath,
    this.fileSize,
    this.actualResolution,
    this.actualExtension,
    this.notice,
    this.startedAt,
    this.finishedAt,
    this.attempts = 0,
  });

  final String id;
  final DownloadRequest request;
  final TaskStatus status;
  final DateTime createdAt;
  final DownloadProgress progress;
  final AppError? error;
  final String? filePath;
  final int? fileSize;
  final int? actualResolution;
  final String? actualExtension;

  /// Informational message, e.g. "1080p wasn't available; downloaded 720p".
  final String? notice;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int attempts;

  MediaEntry get entry => request.entry;
  DownloadOptions get options => request.options;
  String get title => entry.title;

  DownloadTask copyWith({
    TaskStatus? status,
    DownloadProgress? progress,
    AppError? error,
    bool clearError = false,
    String? filePath,
    int? fileSize,
    int? actualResolution,
    String? actualExtension,
    String? notice,
    bool clearNotice = false,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    int? attempts,
  }) =>
      DownloadTask(
        id: id,
        request: request,
        createdAt: createdAt,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
        filePath: filePath ?? this.filePath,
        fileSize: fileSize ?? this.fileSize,
        actualResolution: actualResolution ?? this.actualResolution,
        actualExtension: actualExtension ?? this.actualExtension,
        notice: clearNotice ? null : (notice ?? this.notice),
        startedAt: startedAt ?? this.startedAt,
        finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
        attempts: attempts ?? this.attempts,
      );
}
