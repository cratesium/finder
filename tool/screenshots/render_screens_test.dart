// Renders each screen to PNG with real fonts for visual review.
//
//   flutter test tool/screenshots/render_screens_test.dart
//
// Output: build/screenshots/*.png. Not part of the regular test suite.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coursegrab/core/errors/app_error.dart';
import 'package:coursegrab/core/routing/routes.dart';
import 'package:coursegrab/features/downloads/application/download_providers.dart';
import 'package:coursegrab/models/download_options.dart';
import 'package:coursegrab/models/history_record.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_output_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/fakes.dart';
import '../../test/helpers/harness.dart';

Future<void> loadFonts() async {
  final root = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$root/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$root/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

Future<void> snap(WidgetTester tester, String name) async {
  await idle(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screenshots/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadFonts);

  testWidgets('render screens', (tester) async {
    final h = Harness();
    final container = await h.pump(tester);
    await snap(tester, '1-dashboard-empty');

    await tester.enterText(find.byKey(const Key('url-field')), 'https://www.youtube.com/playlist?list=PL1');
    await tester.tap(find.byKey(const Key('detect-button')));
    await snap(tester, '2-dashboard-playlist');

    final m = container.read(downloadManagerProvider)..maxConcurrent = 2;
    await tester.runAsync(() => m.enqueue([
          request('a1', dir: '/tmp/cg-widget/Downloads', playlist: 'Flutter Desktop Course'),
          request('b2', dir: '/tmp/cg-widget/Downloads', playlist: 'Flutter Desktop Course',
              options: const DownloadOptions(destinationDir: '/tmp/cg-widget/Downloads', quality: VideoQuality.p1080)),
          request('c3', dir: '/tmp/cg-widget/Downloads'),
          request('d4', dir: '/tmp/cg-widget/Downloads'),
          request('e5', dir: '/tmp/cg-widget/Downloads'),
        ]));
    await idle(tester);
    h.downloader.jobs[0].emit(const ProgressEvent(
        status: 'downloading', downloadedBytes: 48234496, totalBytes: 131072000, speed: 4718592, eta: 17, formatId: '137'));
    h.downloader.jobs[1].emit(const ProgressEvent(
        status: 'downloading', downloadedBytes: 9437184, totalBytesEstimate: 12582912, speed: 1048576, eta: 3, formatId: '140'));
    await idle(tester);
    h.downloader.jobs[1].emit(const ProgressEvent(
        status: 'downloading', downloadedBytes: 9437184, totalBytesEstimate: 12582912, speed: 1048576, eta: 3, formatId: '251'));
    await idle(tester);
    await tester.tap(find.text('Downloads').first);
    await snap(tester, '3-downloads');

    await tester.tap(find.text('Queue').first);
    await snap(tester, '4-queue');

    h.downloader.jobs[0].succeed('/tmp/x.mp4', res: 720);
    h.downloader.jobs[1].fail(AppError.of(AppErrorKind.network));
    await idle(tester);
    for (var i = 0; i < 2; i++) {
      await h.history.upsert(HistoryRecord(
        dedupeKey: 'h$i',
        videoId: 'h$i',
        extractor: 'Youtube',
        title: ['Lesson 01 — Project setup', 'Lesson 02 — Widgets and layout'][i],
        url: 'https://youtube.com/watch?v=h$i',
        destinationDir: '/tmp/cg-widget/Downloads/Flutter Desktop Course',
        playlistTitle: 'Flutter Desktop Course',
        status: i == 0 ? HistoryStatus.completed : HistoryStatus.interrupted,
        createdAt: DateTime(2026, 11, 4, 18, 30 + i),
        completedAt: i == 0 ? DateTime(2026, 11, 4, 18, 42) : null,
        options: const DownloadOptions(destinationDir: '/tmp'),
        resolution: '1080p',
        format: 'mp4',
        fileSize: 214958080,
        filePath: '/tmp/missing.mp4',
        errorMessage: i == 1 ? 'CourseGrab was closed before this download finished.' : null,
      ));
    }
    await tester.tap(find.text('History').first);
    await snap(tester, '5-history');

    await tester.tap(find.text('Settings').first);
    await snap(tester, '6-settings');

    await tester.tap(find.text('About').first);
    await snap(tester, '7-about');

    tester.view.physicalSize = const ui.Size(900, 700);
    await idle(tester);
    await tester.tap(find.byTooltip('Dashboard'));
    await snap(tester, '8-dashboard-narrow');

    await tester.runAsync(m.shutdown);
    await idle(tester);
  });

  testWidgets('render light theme + missing deps', (tester) async {
    final h = Harness()..deps = missingSnapshot;
    await h.pump(tester, location: Routes.settings);
    await snap(tester, '9-settings-missing');
  });
}
