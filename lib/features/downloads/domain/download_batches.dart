import '../../../models/download_task.dart';

/// A playlist download: the tasks created together from one playlist.
class DownloadBatch {
  DownloadBatch(this.id, this.title, this.tasks);

  final String id;
  final String title;
  final List<DownloadTask> tasks;

  int get total => tasks.length;
  int count(bool Function(TaskStatus) test) => tasks.where((t) => test(t.status)).length;

  int get completed => count((s) => s == TaskStatus.completed);
  int get skipped => count((s) => s == TaskStatus.skipped);
  int get failed => count((s) => s == TaskStatus.failed);
  int get cancelled => count((s) => s == TaskStatus.cancelled);
  int get active => count((s) => s.isActive);
  int get paused => count((s) => s == TaskStatus.paused);
  int get pending => count((s) => s == TaskStatus.queued);

  bool get isFinished => tasks.every((t) => t.status.isTerminal);
  bool get hasRetryable => failed + cancelled > 0;
  bool get hasRunnable => tasks.any((t) => t.status.isActive || t.status == TaskStatus.queued);

  /// Overall progress 0..1: finished items count fully, running items by their
  /// real reported fraction (0 when the source hasn't reported a size yet).
  double get fraction {
    if (tasks.isEmpty) return 0;
    var sum = 0.0;
    for (final t in tasks) {
      if (t.status.isTerminal) {
        sum += 1;
      } else if (t.status.isActive || t.status == TaskStatus.paused) {
        sum += t.progress.fraction ?? 0;
      }
    }
    return (sum / tasks.length).clamp(0.0, 1.0);
  }

  /// Aggregate download speed of running items (bytes/s), if reported.
  double? get speed {
    final speeds = tasks
        .where((t) => t.status == TaskStatus.downloading)
        .map((t) => t.progress.speed)
        .whereType<double>()
        .toList();
    return speeds.isEmpty ? null : speeds.reduce((a, b) => a + b);
  }

  /// Plain-language result, e.g. "12 downloaded · 1 failed · 2 skipped".
  String get summary => [
    '$completed downloaded',
    if (skipped > 0) '$skipped already downloaded',
    if (failed > 0) '$failed failed',
    if (cancelled > 0) '$cancelled cancelled',
  ].join(' · ');
}

/// Row in the downloads list: a lone task or a playlist batch.
sealed class DownloadListItem {
  const DownloadListItem();
}

class SingleItem extends DownloadListItem {
  const SingleItem(this.task);
  final DownloadTask task;
}

class BatchItem extends DownloadListItem {
  const BatchItem(this.batch);
  final DownloadBatch batch;
}

/// Groups tasks that share a `batchId` (keeping the first occurrence's
/// position); tasks without one, and batches of a single item, stay as is.
List<DownloadListItem> groupIntoBatches(List<DownloadTask> tasks) {
  final byBatch = <String, List<DownloadTask>>{};
  for (final t in tasks) {
    final id = t.request.batchId;
    if (id != null) (byBatch[id] ??= []).add(t);
  }
  final emitted = <String>{};
  final out = <DownloadListItem>[];
  for (final t in tasks) {
    final id = t.request.batchId;
    final group = id == null ? null : byBatch[id];
    if (group == null || group.length < 2) {
      out.add(SingleItem(t));
    } else if (emitted.add(id!)) {
      out.add(BatchItem(DownloadBatch(id, t.request.playlistTitle ?? 'Playlist', group)));
    }
  }
  return out;
}
