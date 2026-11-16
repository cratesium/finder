import 'package:finder/features/downloads/domain/download_batches.dart';
import 'package:finder/models/download_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

DownloadTask task(String id, TaskStatus status, {String? batch, DownloadProgress? progress}) => DownloadTask(
  id: id,
  request: request(id, playlist: batch == null ? null : 'Course', batch: batch),
  status: status,
  createdAt: DateTime(2026),
  progress: progress ?? const DownloadProgress(),
);

void main() {
  group('groupIntoBatches', () {
    test('groups playlist items into one batch at the first item\'s position', () {
      final items = groupIntoBatches([
        task('solo', TaskStatus.completed),
        task('a', TaskStatus.downloading, batch: 'b1'),
        task('other', TaskStatus.queued),
        task('b', TaskStatus.queued, batch: 'b1'),
      ]);
      expect(items, hasLength(3));
      expect((items[0] as SingleItem).task.id, 'solo');
      final batch = (items[1] as BatchItem).batch;
      expect(batch.title, 'Course');
      expect(batch.tasks.map((t) => t.id), ['a', 'b']);
      expect((items[2] as SingleItem).task.id, 'other');
    });

    test('a batch with a single remaining item is shown as a plain task', () {
      final items = groupIntoBatches([task('a', TaskStatus.queued, batch: 'b1')]);
      expect(items.single, isA<SingleItem>());
    });
  });

  group('DownloadBatch', () {
    test('overall progress counts finished items fully and running ones by real fraction', () {
      final b = DownloadBatch('b', 'Course', [
        task('1', TaskStatus.completed, batch: 'b'),
        task('2', TaskStatus.failed, batch: 'b'),
        task(
          '3',
          TaskStatus.downloading,
          batch: 'b',
          progress: const DownloadProgress(downloadedBytes: 50, totalBytes: 100, speed: 1000),
        ),
        task('4', TaskStatus.queued, batch: 'b'),
      ]);
      expect(b.fraction, closeTo((1 + 1 + 0.5 + 0) / 4, 1e-9));
      expect(b.completed, 1);
      expect(b.failed, 1);
      expect(b.active, 1);
      expect(b.pending, 1);
      expect(b.isFinished, isFalse);
      expect(b.hasRetryable, isTrue);
      expect(b.speed, 1000);
    });

    test('summary after completion', () {
      final b = DownloadBatch('b', 'Course', [
        task('1', TaskStatus.completed, batch: 'b'),
        task('2', TaskStatus.completed, batch: 'b'),
        task('3', TaskStatus.skipped, batch: 'b'),
        task('4', TaskStatus.failed, batch: 'b'),
      ]);
      expect(b.isFinished, isTrue);
      expect(b.fraction, 1);
      expect(b.summary, '2 downloaded · 1 already downloaded · 1 failed');
    });
  });
}
