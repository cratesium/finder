import 'package:coursegrab/app.dart';
import 'package:coursegrab/core/config/app_paths.dart';
import 'package:coursegrab/core/di/providers.dart';
import 'package:coursegrab/core/routing/app_router.dart';
import 'package:coursegrab/core/routing/routes.dart';
import 'package:coursegrab/features/settings/application/dependency_controller.dart';
import 'package:coursegrab/models/app_settings.dart';
import 'package:coursegrab/models/dependency_status.dart';
import 'package:coursegrab/models/media_info.dart';
import 'package:coursegrab/services/trust_store_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const testPaths = AppPaths(
  dataDir: '/tmp/cg-widget',
  binDir: '/tmp/cg-widget/bin',
  logDir: '/tmp/cg-widget/logs',
  databasePath: ':memory:',
  defaultDownloadDir: '/tmp/cg-widget/Downloads',
);

final samplePlaylist = MediaInfo(
  kind: MediaKind.playlist,
  id: 'PL1',
  title: 'Flutter Desktop Course',
  sourceUrl: 'https://www.youtube.com/playlist?list=PL1',
  extractor: 'YoutubeTab',
  uploader: 'Teacher',
  entries: [
    entry('a', title: 'Welcome', index: 1),
    entry('b', title: 'Layouts', index: 2),
    entry('c', title: '[Private video]', index: 3, availability: EntryAvailability.private, duration: null),
  ],
);

final sampleVideo = MediaInfo(
  kind: MediaKind.video,
  id: 'v',
  title: 'Single Lesson',
  sourceUrl: 'https://www.youtube.com/watch?v=v',
  extractor: 'Youtube',
  entries: [
    entry('v', title: 'Single Lesson', formats: const [
      MediaFormat(formatId: '136', width: 1280, height: 720, vcodec: 'avc1', acodec: 'none'),
      MediaFormat(formatId: '140', vcodec: 'none', acodec: 'mp4a'),
    ]),
  ],
);

/// Lets real I/O (filesystem checks) complete, then pumps a bounded number of
/// frames. `pumpAndSettle` can't be used while indeterminate progress
/// indicators are animating.
Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

class Harness {
  final downloader = FakeDownloader();
  final history = FakeHistoryRepository();
  final settingsRepo = FakeSettingsRepository();
  final opener = FakeFileOpener();
  late FakeMetadataService metadata = FakeMetadataService((_) => samplePlaylist);
  DependencySnapshot deps = readySnapshot;

  Future<ProviderContainer> pump(WidgetTester tester, {String location = Routes.dashboard}) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appPathsProvider.overrideWithValue(testPaths),
        initialSettingsProvider.overrideWithValue(const AppSettings(downloadDirectory: '/tmp/cg-widget/Downloads')),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        historyRepositoryProvider.overrideWithValue(history),
        metadataServiceProvider.overrideWithValue(metadata),
        downloaderServiceProvider.overrideWithValue(downloader),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        fileOpenerProvider.overrideWithValue(opener),
        directoryPickerProvider.overrideWithValue(FakeDirectoryPicker()),
        dependencyProvider.overrideWith(() => FakeDependencyController(deps)),
        ytDlpNetworkProvider.overrideWith((ref) => YtDlpNetworkConfig.none),
      ],
      child: CourseGrabApp(router: buildRouter(initialLocation: location)),
    );
    await tester.pumpWidget(scope);
    await idle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(CourseGrabApp)));
  }
}

