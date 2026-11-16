import 'package:finder/models/download_task.dart';
import 'package:finder/services/android/android_background_sync.dart';
import 'package:finder/services/android/android_toolchain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

DownloadTask task(String id, TaskStatus s, {int? done, int? total}) => DownloadTask(
  id: id,
  request: request(id),
  status: s,
  createdAt: DateTime(2026),
  progress: DownloadProgress(downloadedBytes: done, totalBytes: total),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ForegroundStatus', () {
    test('counts active, queued and finished tasks; paused tasks do not keep it alive', () {
      final s = ForegroundStatus.of([
        task('a', TaskStatus.downloading, done: 50, total: 100),
        task('b', TaskStatus.queued),
        task('c', TaskStatus.completed),
        task('d', TaskStatus.paused),
        task('e', TaskStatus.failed),
      ]);
      expect(s.active, 1);
      expect(s.queued, 1);
      expect(s.title, 'Video a');
      expect(s.progress, closeTo(0.5, 1e-9));
      expect(s.completed, 1);
      expect(s.total, 3);
      expect(s.isIdle, isFalse);
      expect(ForegroundStatus.of([task('d', TaskStatus.paused)]).isIdle, isTrue);
    });

    test('progress is indeterminate unless every active task knows its size', () {
      final s = ForegroundStatus.of([
        task('a', TaskStatus.downloading, done: 50, total: 100),
        task('b', TaskStatus.preparing),
      ]);
      expect(s.progress, isNull);
    });
  });

  group('AndroidBackgroundSync', () {
    late List<MethodCall> calls;
    late AndroidToolchain toolchain;

    setUp(() {
      calls = [];
      const channel = MethodChannel('test/toolchain');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return true;
      });
      toolchain = AndroidToolchain(method: channel, events: const EventChannel('test/toolchain/events'));
    });

    List<MethodCall> status() => calls.where((c) => c.method == 'setForegroundStatus').toList();

    test('sends state changes immediately and throttles progress-only updates', () async {
      final sync = AndroidBackgroundSync(toolchain, minInterval: const Duration(milliseconds: 200));
      sync.update([task('a', TaskStatus.downloading, done: 10, total: 100)]);
      await Future<void>.delayed(Duration.zero);
      expect(status(), hasLength(1));
      expect(calls.any((c) => c.method == 'ensureNotificationPermission'), isTrue);

      // Progress-only changes are coalesced.
      sync.update([task('a', TaskStatus.downloading, done: 20, total: 100)]);
      sync.update([task('a', TaskStatus.downloading, done: 30, total: 100)]);
      await Future<void>.delayed(Duration.zero);
      expect(status(), hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(status(), hasLength(2));
      expect((status().last.arguments as Map)['progress'], closeTo(0.3, 1e-9));

      // Becoming idle is sent right away so the service can stop.
      sync.update([task('a', TaskStatus.completed)]);
      await Future<void>.delayed(Duration.zero);
      expect(status(), hasLength(3));
      expect((status().last.arguments as Map)['active'], 0);
      sync.dispose();
    });

    test('identical snapshots are not resent', () async {
      final sync = AndroidBackgroundSync(toolchain, minInterval: Duration.zero);
      sync.update([task('a', TaskStatus.queued)]);
      sync.update([task('a', TaskStatus.queued)]);
      await Future<void>.delayed(Duration.zero);
      expect(status(), hasLength(1));
      sync.dispose();
    });
  });
}
