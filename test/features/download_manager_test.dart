import 'dart:async';
import 'dart:io';

import 'package:finder/core/errors/app_error.dart';
import 'package:finder/features/downloads/domain/download_manager.dart';
import 'package:finder/models/download_options.dart';
import 'package:finder/models/download_task.dart';
import 'package:finder/models/history_record.dart';
import 'package:finder/models/media_info.dart';
import 'package:finder/services/ytdlp/ytdlp_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Lets microtasks and zero-delay timers run.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeDownloader downloader;
  late FakeHistoryRepository history;
  late FakeNotifications notifications;
  late Directory tmp;
  ResolvedTools tools = const ResolvedTools(ytDlpPath: '/y', ffmpegPath: '/f');

  DownloadManager build({int max = 2, bool skip = true}) => DownloadManager(
        downloader: downloader,
        history: history,
        notifications: notifications,
        tools: () async => tools,
        directoryCheck: (_) async => true,
        fileSize: (_) async => 1234,
        maxConcurrent: max,
        skipCompleted: skip,
        progressThrottle: Duration.zero,
      );

  setUp(() async {
    downloader = FakeDownloader();
    history = FakeHistoryRepository();
    notifications = FakeNotifications();
    tools = const ResolvedTools(ytDlpPath: '/y', ffmpegPath: '/f');
    tmp = await Directory.systemTemp.createTemp('cg-mgr');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('respects the concurrency limit and starts the next task when one finishes', () async {
    final m = build(max: 2);
    final r = await m.enqueue([request('a'), request('b'), request('c')]);
    await settle();
    expect(r.added, 3);
    expect(downloader.jobs, hasLength(2));
    expect(m.tasks.map((t) => t.status), [TaskStatus.preparing, TaskStatus.preparing, TaskStatus.queued]);
    expect(m.queuePosition(m.tasks[2].id), 1);

    downloader.jobs[0].succeed('/out/a.mp4');
    await settle();
    expect(m.tasks[0].status, TaskStatus.completed);
    expect(downloader.jobs, hasLength(3));
    expect(m.tasks[2].status, isNot(TaskStatus.queued));
  });

  test('increasing concurrency starts waiting tasks immediately', () async {
    final m = build(max: 1);
    await m.enqueue([request('a'), request('b'), request('c')]);
    await settle();
    expect(downloader.jobs, hasLength(1));
    m.maxConcurrent = 3;
    await settle();
    expect(downloader.jobs, hasLength(3));
  });

  test('prevents duplicate active tasks', () async {
    final m = build();
    await m.enqueue([request('a')]);
    final r = await m.enqueue([request('a'), request('b')]);
    expect(r.duplicates, 1);
    expect(r.added, 1);
    expect(m.tasks, hasLength(2));
  });

  test('same video into a different folder or format is not a duplicate', () async {
    final m = build();
    await m.enqueue([request('a', dir: '/one')]);
    final r = await m.enqueue([
      request('a', dir: '/two'),
      request('a', dir: '/one', options: const DownloadOptions(destinationDir: '/one', mode: DownloadMode.audioOnly)),
    ]);
    expect(r.added, 2);
  });

  test('skips videos already completed in history when the file exists', () async {
    final file = File('${tmp.path}/a.mp4')..writeAsStringSync('x');
    final req = request('a', dir: tmp.path);
    await history.upsert(HistoryRecord(
      dedupeKey: req.dedupeKey,
      videoId: 'a',
      extractor: 'Youtube',
      title: 'A',
      url: req.entry.url,
      destinationDir: tmp.path,
      status: HistoryStatus.completed,
      createdAt: DateTime(2026),
      options: req.options,
      filePath: file.path,
    ));
    final m = build();
    final r = await m.enqueue([req]);
    expect(r.skippedCompleted, 1);
    expect(m.tasks.single.status, TaskStatus.skipped);
    expect(downloader.jobs, isEmpty);

    // If the file was deleted, it downloads again.
    file.deleteSync();
    m.clearFinished();
    final r2 = await m.enqueue([req]);
    expect(r2.added, 1);
  });

  test('unavailable entries are not queued', () async {
    final m = build();
    final r = await m.enqueue([
      DownloadRequest(
        entry: entry('p', availability: EntryAvailability.private),
        options: const DownloadOptions(destinationDir: '/d'),
      ),
    ]);
    expect(r.unavailable, 1);
    expect(m.tasks, isEmpty);
  });

  test('reports real progress, stream changes and post-processing', () async {
    final m = build();
    await m.enqueue([request('a')]);
    await settle();
    final job = downloader.jobs.single;
    job.emit(const ProgressEvent(status: 'downloading', downloadedBytes: 50, totalBytes: 100, speed: 10, eta: 5, formatId: '137'));
    await settle();
    var t = m.tasks.single;
    expect(t.status, TaskStatus.downloading);
    expect(t.progress.fraction, 0.5);
    expect(t.progress.speed, 10);
    expect(t.progress.etaSeconds, 5);
    expect(t.progress.streamIndex, 1);

    job.emit(const ProgressEvent(status: 'downloading', downloadedBytes: 5, totalBytesEstimate: 20, formatId: '140'));
    await settle();
    t = m.tasks.single;
    expect(t.progress.streamIndex, 2);
    expect(t.progress.totalBytesIsEstimate, isTrue);

    job.emit(const PostProcessEvent(status: 'started', postprocessor: 'Merger'));
    await settle();
    expect(m.tasks.single.status, TaskStatus.processing);
    expect(m.tasks.single.progress.phaseLabel, 'Merging audio and video');
  });

  test('completion records history, size, resolution and notifies', () async {
    final m = build();
    await m.enqueue([request('a', options: const DownloadOptions(destinationDir: '/d', quality: VideoQuality.p1080))]);
    await settle();
    downloader.jobs.single.succeed('/d/A [a].mp4', res: 1080);
    await settle();
    final t = m.tasks.single;
    expect(t.status, TaskStatus.completed);
    expect(t.fileSize, 1234);
    expect(t.notice, isNull);
    final rec = history.byKey.values.single;
    expect(rec.status, HistoryStatus.completed);
    expect(rec.resolution, '1080p');
    expect(rec.filePath, '/d/A [a].mp4');
    expect(notifications.shown.single, startsWith('Download complete'));
  });

  test('falls back to ffprobe when yt-dlp reports no resolution', () async {
    final m = DownloadManager(
      downloader: downloader,
      history: history,
      tools: () async => tools,
      directoryCheck: (_) async => true,
      fileSize: (_) async => 1,
      resolutionProbe: (ffmpeg, file) async => ffmpeg == '/f' ? 480 : null,
    );
    await m.enqueue([request('a', options: const DownloadOptions(destinationDir: '/d', quality: VideoQuality.p1080))]);
    await settle();
    downloader.jobs.single.succeed('/d/a.mp4');
    await settle();
    expect(m.tasks.single.actualResolution, 480);
    expect(m.tasks.single.notice, contains('480p'));
  });

  test('communicates when the requested quality was unavailable', () async {
    final m = build();
    await m.enqueue([request('a', options: const DownloadOptions(destinationDir: '/d', quality: VideoQuality.p2160))]);
    await settle();
    downloader.jobs.single.succeed('/d/a.mp4', res: 720);
    await settle();
    expect(m.tasks.single.notice, contains('wasn\'t available'));
    expect(m.tasks.single.notice, contains('720p'));
  });

  test('failure is recorded and can be retried', () async {
    final m = build();
    await m.enqueue([request('a')]);
    await settle();
    downloader.jobs.single.fail(AppError.of(AppErrorKind.network));
    await settle();
    expect(m.tasks.single.status, TaskStatus.failed);
    expect(m.tasks.single.error!.kind, AppErrorKind.network);
    expect(history.byKey.values.single.status, HistoryStatus.failed);

    m.retry(m.tasks.single.id);
    await settle();
    expect(downloader.jobs, hasLength(2));
    expect(m.tasks.single.attempts, 2);
    expect(m.tasks.single.error, isNull);
  });

  test('missing yt-dlp or FFmpeg fails with a helpful message', () async {
    tools = const ResolvedTools();
    final m = build();
    await m.enqueue([request('a')]);
    await settle();
    expect(m.tasks.single.status, TaskStatus.failed);
    expect(m.tasks.single.error!.kind, AppErrorKind.missingDependency);
    expect(downloader.jobs, isEmpty);

    tools = const ResolvedTools(ytDlpPath: '/y');
    m.retry(m.tasks.single.id);
    await settle();
    expect(m.tasks.single.error!.message, contains('FFmpeg'));
  });

  test('unwritable destination fails with a permission error', () async {
    final m = DownloadManager(
      downloader: downloader,
      history: history,
      tools: () async => tools,
      directoryCheck: (_) async => false,
    );
    await m.enqueue([request('a')]);
    await settle();
    expect(m.tasks.single.error!.kind, AppErrorKind.permission);
  });

  test('pause stops the process and resume restarts it', () async {
    final m = build();
    await m.enqueue([request('a')]);
    await settle();
    final id = m.tasks.single.id;
    await m.pause(id);
    await settle();
    expect(downloader.jobs.single.stopped, isTrue);
    expect(m.tasks.single.status, TaskStatus.paused);
    expect(m.activeCount, 0);

    m.resume(id);
    await settle();
    expect(downloader.jobs, hasLength(2));
    expect(m.tasks.single.status, TaskStatus.preparing);
  });

  test('cancel stops active and waiting tasks', () async {
    final m = build(max: 1);
    await m.enqueue([request('a'), request('b')]);
    await settle();
    await m.cancel(m.tasks[0].id);
    await settle();
    expect(downloader.jobs[0].stopped, isTrue);
    expect(m.tasks[0].status, TaskStatus.cancelled);
    // The next task started after the cancellation freed the slot.
    expect(downloader.jobs, hasLength(2));
    await m.cancel(m.tasks[1].id);
    await settle();
    expect(m.tasks[1].status, TaskStatus.cancelled);
    expect(history.byKey.values.map((r) => r.status), everyElement(HistoryStatus.cancelled));
  });

  test('queue pause holds new starts', () async {
    final m = build(max: 1);
    m.queuePaused = true;
    await m.enqueue([request('a')]);
    await settle();
    expect(downloader.jobs, isEmpty);
    m.queuePaused = false;
    await settle();
    expect(downloader.jobs, hasLength(1));
  });

  test('reordering waiting tasks', () async {
    final m = build(max: 1);
    await m.enqueue([request('a'), request('b'), request('c'), request('d')]);
    await settle();
    final ids = m.tasks.map((t) => t.id).toList();
    m.move(ids[3], -1);
    expect(m.tasks.map((t) => t.entry.id), ['a', 'b', 'd', 'c']);
    m.moveToTop(ids[3]);
    expect(m.tasks.map((t) => t.entry.id), ['a', 'd', 'b', 'c']);
    expect(m.queuePosition(ids[3]), 1);
  });

  test('change stream emits task lists', () async {
    final m = build();
    final emissions = <List<DownloadTask>>[];
    final sub = m.changes.listen(emissions.add);
    await m.enqueue([request('a')]);
    await settle();
    expect(emissions, isNotEmpty);
    expect(emissions.last.single.entry.id, 'a');
    await sub.cancel();
  });

  test('shutdown stops active downloads and marks them interrupted', () async {
    final m = build();
    await m.enqueue([request('a'), request('b'), request('c')]);
    await settle();
    await m.shutdown();
    expect(downloader.jobs.every((j) => j.stopped), isTrue);
    final statuses = history.byKey.values.map((r) => r.status).toList();
    expect(statuses.where((s) => s == HistoryStatus.interrupted), hasLength(2));
  });

  test('history write failures do not break downloads', () async {
    history.failWrites = true;
    final m = build();
    await m.enqueue([request('a')]);
    await settle();
    downloader.jobs.single.succeed('/x.mp4');
    await settle();
    expect(m.tasks.single.status, TaskStatus.completed);
  });

  test('temporary artifact detection never matches final media', () {
    const stem = 'Lesson [abc]';
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].f137.mp4.part', stem), isTrue);
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].f140.m4a', stem), isTrue);
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].mp4.part', stem), isTrue);
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].mp4.ytdl', stem), isTrue);
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].temp.mp4', stem), isTrue);
    expect(DownloadManager.isTemporaryArtifact('Lesson [abc].mp4', stem), isFalse);
    expect(DownloadManager.isTemporaryArtifact('Other [xyz].mp4.part', stem), isFalse);
  });

  test('EnqueueResult describes outcomes', () {
    expect(const EnqueueResult(added: 2, duplicates: 1).describe(), '2 added to the queue, 1 already queued.');
    expect(const EnqueueResult().describe(), 'Nothing to download.');
  });

  test('slow tool resolution keeps tasks preparing and does not over-start', () async {
    final gate = Completer<void>();
    final m = DownloadManager(
      downloader: downloader,
      history: history,
      tools: () async {
        await gate.future;
        return tools;
      },
      directoryCheck: (_) async => true,
      maxConcurrent: 1,
    );
    await m.enqueue([request('a'), request('b')]);
    await settle();
    expect(m.tasks.map((t) => t.status), [TaskStatus.preparing, TaskStatus.queued]);
    gate.complete();
    await settle();
    expect(downloader.jobs, hasLength(1));
  });
}
