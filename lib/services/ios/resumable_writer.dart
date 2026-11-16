import 'dart:async';
import 'dart:io';

import '../../core/errors/app_error.dart';

/// Opens a byte stream starting at [start] (an HTTP range offset).
typedef ByteSource = Stream<List<int>> Function(int start);

class WriteProgress {
  const WriteProgress({required this.downloaded, this.total, this.speed, this.eta});
  final int downloaded;
  final int? total;

  /// Bytes per second, smoothed. Null until there's a measurement.
  final double? speed;
  final int? eta;
}

enum WriteResult { completed, stopped }

/// Writes a stream to a `.part` file, resuming from the bytes already on disk.
///
/// Stopping keeps the partial file so a later call continues from where it
/// left off (YouTube serves byte ranges). Progress and speed are measured from
/// the bytes actually received; nothing is estimated.
class ResumableWriter {
  ResumableWriter({DateTime Function()? clock, this.tick = const Duration(milliseconds: 400)})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration tick;
  Completer<void>? _stop;

  /// Stops the current [write] (if any). Safe to call at any time.
  void stop() {
    final s = _stop;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<WriteResult> write({
    required File partial,
    required ByteSource source,
    required int? totalBytes,
    required void Function(WriteProgress) onProgress,
    bool resumable = true,
  }) async {
    final stop = _stop = Completer<void>();
    var offset = 0;
    if (await partial.exists()) {
      offset = await partial.length();
      if (!resumable || (totalBytes != null && offset > totalBytes)) {
        await partial.delete();
        offset = 0;
      }
    }
    if (totalBytes != null && offset == totalBytes && offset > 0) {
      onProgress(WriteProgress(downloaded: offset, total: totalBytes));
      return WriteResult.completed;
    }
    await partial.parent.create(recursive: true);

    final sink = partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    var received = offset;
    var lastTime = _clock();
    var lastBytes = received;
    double? speed;
    final done = Completer<WriteResult>();

    void report({bool force = false}) {
      final now = _clock();
      final elapsed = now.difference(lastTime);
      if (!force && elapsed < tick) return;
      if (elapsed.inMicroseconds > 0) {
        final instant = (received - lastBytes) * 1e6 / elapsed.inMicroseconds;
        speed = speed == null ? instant : speed! * 0.7 + instant * 0.3;
      }
      lastTime = now;
      lastBytes = received;
      final s = speed;
      final eta = (totalBytes != null && s != null && s > 0) ? ((totalBytes - received) / s).ceil() : null;
      onProgress(WriteProgress(downloaded: received, total: totalBytes, speed: s, eta: eta));
    }

    onProgress(WriteProgress(downloaded: received, total: totalBytes));
    late final StreamSubscription<List<int>> sub;
    sub = source(offset).listen(
      (chunk) {
        // Data arriving after a stop is dropped; the sink may already be closed.
        if (done.isCompleted) return;
        sink.add(chunk);
        received += chunk.length;
        report();
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
        sub.cancel();
      },
      onDone: () {
        if (!done.isCompleted) done.complete(WriteResult.completed);
      },
      cancelOnError: true,
    );
    unawaited(
      stop.future.then((_) {
        if (!done.isCompleted) done.complete(WriteResult.stopped);
        // Don't await: cancelling a source that is waiting on the network only
        // completes once that wait ends.
        unawaited(sub.cancel());
      }),
    );

    try {
      final result = await done.future;
      await sink.flush();
      await sink.close();
      if (result == WriteResult.completed) {
        if (totalBytes != null && received < totalBytes) {
          throw AppError(
            AppErrorKind.network,
            'The connection ended before the download finished.',
            detail: 'received $received of $totalBytes bytes',
          );
        }
        report(force: true);
      }
      return result;
    } catch (e) {
      await sink.close().catchError((_) {});
      rethrow;
    } finally {
      if (!stop.isCompleted) stop.complete();
    }
  }
}
