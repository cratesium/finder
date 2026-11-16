import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/history/data/history_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../services/android/android_platform_services.dart';
import '../../services/android/android_toolchain.dart';
import '../../services/dependency_manager.dart';
import '../../services/directory_picker.dart';
import '../../services/downloader_service.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/file_opener_service.dart';
import '../../services/metadata_service.dart';
import '../../services/notification_service.dart';
import '../../services/process_service.dart';
import '../../services/ios/ios_bridge.dart';
import '../../services/ios/ios_downloader_service.dart';
import '../../services/ios/ios_metadata_service.dart';
import '../../services/ios/ios_platform_services.dart';
import '../../services/ios/youtube_gateway.dart';
import '../../services/trust_store_service.dart';
import '../config/app_paths.dart';
import '../utils/platform_info.dart';

// Values produced during bootstrap. They are always overridden in main().
final appPathsProvider = Provider<AppPaths>((ref) => throw UnimplementedError('appPathsProvider must be overridden'));
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('databaseProvider must be overridden'));
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('initialSettingsProvider must be overridden'),
);

/// Number of downloads marked interrupted at startup (shown once on launch).
final interruptedAtStartupProvider = Provider<int>((ref) => 0);

final platformInfoProvider = Provider<PlatformInfo>((ref) => PlatformInfo.current());

/// Bridge to the yt-dlp/FFmpeg embedded in the Android app (null elsewhere).
final androidToolchainProvider = Provider<AndroidToolchain?>(
  (ref) => ref.watch(platformInfoProvider).isAndroid ? AndroidToolchain() : null,
);

final processServiceProvider = Provider<ProcessService>((ref) {
  final android = ref.watch(androidToolchainProvider);
  return android != null ? AndroidProcessService(android) : ProcessService.forHost();
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SqliteSettingsRepository(ref.watch(databaseProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => SqliteHistoryRepository(ref.watch(databaseProvider)),
);

final dependencyManagerProvider = Provider<DependencyManager>((ref) {
  final platform = ref.watch(platformInfoProvider);
  if (platform.isIOS) {
    return IosDependencyManager(
      platform: platform,
      processes: ref.watch(processServiceProvider),
      managedBinDir: ref.watch(appPathsProvider).binDir,
    );
  }
  final android = ref.watch(androidToolchainProvider);
  if (android != null) {
    return AndroidDependencyManager(
      platform: platform,
      processes: ref.watch(processServiceProvider),
      managedBinDir: ref.watch(appPathsProvider).binDir,
      toolchain: android,
    );
  }
  return DependencyManager(
    platform: platform,
    processes: ref.watch(processServiceProvider),
    managedBinDir: ref.watch(appPathsProvider).binDir,
  );
});

/// iOS can't run yt-dlp: YouTube is read in Dart (youtube_explode_dart).
/// Null on every other platform.
final youtubeGatewayProvider = Provider<YoutubeGateway?>((ref) {
  if (!ref.watch(platformInfoProvider).isIOS) return null;
  final gateway = YoutubeExplodeGateway();
  ref.onDispose(gateway.close);
  return gateway;
});

final metadataServiceProvider = Provider<MetadataService>((ref) {
  final gateway = ref.watch(youtubeGatewayProvider);
  if (gateway != null) return IosMetadataService(gateway);
  return YtDlpMetadataService(ref.watch(processServiceProvider));
});

final downloaderServiceProvider = Provider<DownloaderService>((ref) {
  final gateway = ref.watch(youtubeGatewayProvider);
  if (gateway != null) {
    const bridge = IosBridge();
    return IosDownloaderService(gateway: gateway, muxer: bridge, background: bridge);
  }
  return YtDlpDownloaderService(ref.watch(processServiceProvider));
});

final ffmpegServiceProvider = Provider<FfmpegService>((ref) => FfmpegService(ref.watch(processServiceProvider)));

final notificationServiceProvider = Provider<NotificationService>((ref) => DesktopNotificationService());

final trustStoreServiceProvider = Provider<TrustStoreService>(
  (ref) => TrustStoreService(platform: ref.watch(platformInfoProvider), dataDir: ref.watch(appPathsProvider).dataDir),
);

final fileOpenerProvider = Provider<FileOpenerService>((ref) {
  if (ref.watch(platformInfoProvider).isIOS) return const IosFileOpener();
  final android = ref.watch(androidToolchainProvider);
  return android != null ? AndroidFileOpener(android) : const SystemFileOpener();
});

final directoryPickerProvider = Provider<DirectoryPicker>((ref) => const NativeDirectoryPicker());
