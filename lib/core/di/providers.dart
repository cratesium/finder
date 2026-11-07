import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/history/data/history_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../services/dependency_manager.dart';
import '../../services/directory_picker.dart';
import '../../services/downloader_service.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/file_opener_service.dart';
import '../../services/metadata_service.dart';
import '../../services/notification_service.dart';
import '../../services/process_service.dart';
import '../../services/trust_store_service.dart';
import '../config/app_paths.dart';
import '../utils/platform_info.dart';

// Values produced during bootstrap. They are always overridden in main().
final appPathsProvider = Provider<AppPaths>(
    (ref) => throw UnimplementedError('appPathsProvider must be overridden'));
final databaseProvider = Provider<Database>(
    (ref) => throw UnimplementedError('databaseProvider must be overridden'));
final initialSettingsProvider = Provider<AppSettings>(
    (ref) => throw UnimplementedError('initialSettingsProvider must be overridden'));

/// Number of downloads marked interrupted at startup (shown once on launch).
final interruptedAtStartupProvider = Provider<int>((ref) => 0);

final platformInfoProvider = Provider<PlatformInfo>((ref) => PlatformInfo.current());

final processServiceProvider = Provider<ProcessService>((ref) => ProcessService.forHost());

final settingsRepositoryProvider = Provider<SettingsRepository>(
    (ref) => SqliteSettingsRepository(ref.watch(databaseProvider)));

final historyRepositoryProvider = Provider<HistoryRepository>(
    (ref) => SqliteHistoryRepository(ref.watch(databaseProvider)));

final dependencyManagerProvider = Provider<DependencyManager>((ref) => DependencyManager(
      platform: ref.watch(platformInfoProvider),
      processes: ref.watch(processServiceProvider),
      managedBinDir: ref.watch(appPathsProvider).binDir,
    ));

final metadataServiceProvider = Provider<MetadataService>(
    (ref) => YtDlpMetadataService(ref.watch(processServiceProvider)));

final downloaderServiceProvider = Provider<DownloaderService>(
    (ref) => YtDlpDownloaderService(ref.watch(processServiceProvider)));

final ffmpegServiceProvider =
    Provider<FfmpegService>((ref) => FfmpegService(ref.watch(processServiceProvider)));

final notificationServiceProvider =
    Provider<NotificationService>((ref) => DesktopNotificationService());

final trustStoreServiceProvider = Provider<TrustStoreService>((ref) => TrustStoreService(
      platform: ref.watch(platformInfoProvider),
      dataDir: ref.watch(appPathsProvider).dataDir,
    ));

final fileOpenerProvider = Provider<FileOpenerService>((ref) => const SystemFileOpener());

final directoryPickerProvider =
    Provider<DirectoryPicker>((ref) => const NativeDirectoryPicker());
