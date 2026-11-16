import 'package:finder/core/errors/app_error.dart';
import 'package:finder/core/routing/routes.dart';
import 'package:finder/features/downloads/application/download_providers.dart';
import 'package:finder/models/dependency_status.dart';
import 'package:finder/models/download_options.dart';
import 'package:finder/models/history_record.dart';
import 'package:finder/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

void main() {
  testWidgets('shell shows navigation and switches screens', (tester) async {
    await Harness().pump(tester);
    for (final label in ['Home', 'Downloads', 'History', 'Settings', 'About']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Queue'), findsNothing); // merged into Downloads
    expect(find.text('Engine ready'), findsOneWidget);

    await tester.tap(find.text('History').first);
    await idle(tester);
    expect(find.text('No history yet'), findsOneWidget);

    await tester.tap(find.text('About').first);
    await idle(tester);
    expect(find.textContaining('Responsible use'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('made-by')), findsOneWidget);
    expect(find.text('Made by '), findsOneWidget);
    expect(find.text('Finder'), findsWidgets);
    expect(find.textContaining('Version 3.'), findsOneWidget);
  });

  testWidgets('dashboard validates URLs before running yt-dlp', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.enterText(find.byKey(const Key('url-field')), 'file:///etc/passwd');
    await tester.tap(find.byKey(const Key('detect-button')));
    await idle(tester);
    expect(find.text('Only http:// and https:// links are supported.'), findsOneWidget);
    expect(h.metadata.calls, 0);
  });

  testWidgets('dashboard detects a playlist, lists videos and enqueues the selection', (tester) async {
    final h = Harness();
    final container = await h.pump(tester);
    await tester.enterText(find.byKey(const Key('url-field')), 'https://www.youtube.com/playlist?list=PL1');
    await tester.tap(find.byKey(const Key('detect-button')));
    await idle(tester);

    expect(find.text('Flutter Desktop Course'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Layouts'), findsOneWidget);
    expect(find.text('1 unavailable'), findsOneWidget);
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.text('Download all 2 videos'), findsOneWidget);
    // A playlist link switches the mode selector automatically.
    expect(h.metadata.lastScope, FetchScope.playlist);

    // Deselect one video.
    await tester.tap(find.text('Layouts'));
    await idle(tester);
    expect(find.text('1 of 2 selected'), findsOneWidget);
    expect(find.text('Download 1 video'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('download-button')));
    await idle(tester);
    await tester.tap(find.byKey(const Key('download-button')));
    await idle(tester);
    expect(find.textContaining('1 added to the queue'), findsOneWidget);

    final tasks = container.read(tasksProvider);
    expect(tasks.single.entry.id, 'a');
    expect(tasks.single.request.playlistTitle, 'Flutter Desktop Course');
    expect(h.downloader.jobs.single.spec.outputTemplate, startsWith('001 - '));
    expect(tasks.single.request.batchId, isNotNull);
  });

  testWidgets('single video only offers resolutions that exist', (tester) async {
    final h = Harness()..metadata = FakeMetadataService((_) => sampleVideo);
    await h.pump(tester);
    await tester.enterText(find.byKey(const Key('url-field')), 'https://www.youtube.com/watch?v=v');
    await tester.tap(find.byKey(const Key('detect-button')));
    await idle(tester);
    expect(find.text('Single Lesson'), findsWidgets);
    expect(find.text('Up to 720p'), findsOneWidget);

    expect(h.metadata.lastScope, FetchScope.single);

    // Resolution chips: only what the video offers can be chosen.
    expect(find.byKey(const Key('quality-chips')), findsOneWidget);
    expect(find.byTooltip('1080p — not offered by this video'), findsOneWidget);
    expect(find.byTooltip('2160p · 4K — not offered by this video'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const Key('quality-chips')), matching: find.text('1080p')));
    await idle(tester);
    expect(find.text('Download video'), findsOneWidget);
    expect(find.textContaining('1080p ·'), findsNothing); // summary unchanged
  });

  testWidgets('mode selector reads only the video from a video-in-playlist link', (tester) async {
    final h = Harness()..metadata = FakeMetadataService((_) => sampleVideo);
    await h.pump(tester);
    await tester.enterText(find.byKey(const Key('url-field')), 'https://www.youtube.com/watch?v=v&list=PL1');
    await idle(tester);
    // Ambiguous link: defaults to Playlist and explains the choice.
    expect(find.textContaining('points to a video inside a playlist'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mode-video')));
    await idle(tester);
    await tester.tap(find.byKey(const Key('detect-button')));
    await idle(tester);
    expect(h.metadata.lastScope, FetchScope.single);
    expect(find.text('Single Lesson'), findsWidgets);
  });

  testWidgets('dashboard explains missing yt-dlp', (tester) async {
    final h = Harness()..deps = missingSnapshot;
    await h.pump(tester);
    expect(find.text('The download engine isn\'t available'), findsOneWidget);
    expect(find.text('Download engine missing'), findsOneWidget);
  });

  testWidgets('metadata errors are shown as friendly messages', (tester) async {
    final h = Harness()..metadata = FakeMetadataService((_) => throw Exception('boom'));
    await h.pump(tester);
    await tester.enterText(find.byKey(const Key('url-field')), 'https://example.com/v');
    await tester.tap(find.byKey(const Key('detect-button')));
    await idle(tester);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('downloads and queue screens show tasks with real progress', (tester) async {
    final h = Harness();
    final container = await h.pump(tester, location: Routes.downloads);
    expect(find.text('No downloads yet'), findsOneWidget);

    final manager = container.read(downloadManagerProvider);
    manager.maxConcurrent = 1;
    await manager.enqueue([
      request('x', dir: '/tmp/cg-widget/Downloads'),
      request('y', dir: '/tmp/cg-widget/Downloads'),
    ]);
    await idle(tester);
    expect(find.text('Video x'), findsOneWidget);
    expect(find.text('Preparing'), findsOneWidget);

    expect(find.text('Video y'), findsOneWidget);
    expect(find.text('Pause queue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-queued')));
    await idle(tester);
    expect(find.text('Video x'), findsNothing);
    expect(find.text('Video y'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);

    h.downloader.jobs.single.succeed('/tmp/cg-widget/Downloads/x.mp4', res: 720);
    await idle(tester);
    await tester.tap(find.byKey(const Key('tab-completed')));
    await idle(tester);
    expect(find.text('Video x'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);

    // Leave no running work behind.
    await manager.shutdown();
    await idle(tester);
  });

  testWidgets('history lists records, flags missing files and supports actions', (tester) async {
    final h = Harness();
    await h.history.upsert(
      HistoryRecord(
        dedupeKey: 'k1',
        videoId: 'v1',
        extractor: 'Youtube',
        title: 'Archived lesson',
        url: 'https://youtube.com/watch?v=v1',
        destinationDir: '/tmp/cg-widget/Downloads',
        status: HistoryStatus.completed,
        createdAt: DateTime(2026, 3, 1),
        completedAt: DateTime(2026, 3, 1),
        options: const DownloadOptions(destinationDir: '/tmp/cg-widget/Downloads'),
        filePath: '/definitely/missing/file.mp4',
        resolution: '1080p',
        format: 'mp4',
        fileSize: 1024 * 1024,
      ),
    );
    await h.pump(tester, location: Routes.history);
    expect(find.text('Archived lesson'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('1080p · MP4'), findsOneWidget);
    expect(find.text('1.0 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions'));
    await idle(tester);
    await tester.tap(find.text('Remove record'));
    await idle(tester);
    expect(find.text('Archived lesson'), findsNothing);
  });

  testWidgets('settings shows dependency status and persists changes', (tester) async {
    final h = Harness();
    await h.pump(tester, location: Routes.settings);
    expect(find.text('yt-dlp'), findsWidgets);
    expect(find.text('FFmpeg'), findsWidgets);
    expect(find.text('2026.10.26'), findsOneWidget);
    expect(find.text('Ready'), findsNWidgets(2));

    final toggle = find.descendant(
      of: find.widgetWithText(FieldRow, 'Number playlist items'),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(toggle);
    await idle(tester);
    await tester.tap(toggle);
    await idle(tester);
    expect(h.settingsRepo.saved?.numberPlaylistItems, isFalse);
  });

  testWidgets('settings explains missing dependencies', (tester) async {
    final h = Harness()..deps = missingSnapshot;
    await h.pump(tester, location: Routes.settings);
    expect(find.text('Missing'), findsNWidgets(2));
    expect(find.textContaining('SHA-256'), findsOneWidget);
  });

  testWidgets('layout adapts to narrow windows', (tester) async {
    final h = Harness();
    await h.pump(tester);
    tester.view.physicalSize = const Size(840, 640);
    await idle(tester);
    // Compact sidebar hides labels, keeps icons + tooltips.
    expect(find.byTooltip('Downloads'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout uses bottom navigation and every screen fits', (tester) async {
    final h = Harness();
    await h.pump(tester);
    tester.view.physicalSize = const Size(390, 844);
    await idle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    const routes = [Routes.home, Routes.downloads, Routes.history, Routes.settings, Routes.about];
    for (final (i, route) in routes.indexed) {
      await tester.tap(find.byType(NavigationDestination).at(i));
      await idle(tester);
      expect(tester.takeException(), isNull, reason: 'overflow on $route');
    }
    // A detected playlist with its options panel must also fit.
    await tester.tap(find.byType(NavigationDestination).first);
    await idle(tester);
    await tester.enterText(find.byType(TextField).first, 'https://www.youtube.com/playlist?list=PL123');
    await tester.tap(find.text('Analyze'));
    await idle(tester);
    expect(tester.takeException(), isNull, reason: 'overflow on detected playlist');
  });

  testWidgets('theme can be switched from Settings and is saved', (tester) async {
    final h = Harness();
    await h.pump(tester, location: Routes.settings);
    await tester.tap(find.text('Light'));
    await idle(tester);
    expect(h.settingsRepo.saved?.theme.name, 'light');
    expect(Theme.of(tester.element(find.text('Settings').first)).brightness, Brightness.light);
  });

  testWidgets('playlist downloads are grouped with overall progress and a summary', (tester) async {
    final h = Harness();
    final container = await h.pump(tester, location: Routes.downloads);
    final manager = container.read(downloadManagerProvider);
    manager.maxConcurrent = 1;
    await manager.enqueue([
      request('p1', dir: '/tmp/cg-widget/Downloads', playlist: 'Course', batch: 'b1'),
      request('p2', dir: '/tmp/cg-widget/Downloads', playlist: 'Course', batch: 'b1'),
    ]);
    await idle(tester);
    expect(find.textContaining('Playlist · 0 of 2 done'), findsOneWidget);
    expect(find.text('1 pending'), findsOneWidget);

    h.downloader.jobs.last.succeed('/tmp/cg-widget/Downloads/Course/p1.mp4', res: 720);
    await idle(tester);
    h.downloader.jobs.last.fail(AppError.of(AppErrorKind.network));
    await idle(tester);
    expect(find.text('Playlist finished with errors'), findsOneWidget);
    expect(find.textContaining('1 downloaded · 1 failed'), findsWidgets);
    expect(find.byTooltip('Retry failed and cancelled'), findsOneWidget);

    await manager.shutdown();
    await idle(tester);
  });

  test('dependency snapshot helpers', () {
    expect(readySnapshot.allReady, isTrue);
    expect(missingSnapshot.of(DependencyKind.ffmpeg).isReady, isFalse);
  });
}
