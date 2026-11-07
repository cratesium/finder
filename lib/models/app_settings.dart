import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import 'download_options.dart';

enum ThemePreference {
  dark('Dark'),
  light('Light'),
  system('Match system');

  const ThemePreference(this.label);
  final String label;

  static ThemePreference fromName(String? n) =>
      values.firstWhere((v) => v.name == n, orElse: () => ThemePreference.dark);
}

/// User preferences persisted in SQLite.
class AppSettings {
  const AppSettings({
    required this.downloadDirectory,
    this.defaultMode = DownloadMode.video,
    this.defaultQuality = VideoQuality.best,
    this.defaultContainer = ContainerFormat.mp4,
    this.defaultAudioFormat = AudioFormat.original,
    this.defaultAudioQuality = AudioQuality.best,
    this.maxConcurrentDownloads = 2,
    this.numberPlaylistItems = true,
    this.skipCompleted = true,
    this.ytDlpPath,
    this.ffmpegPath,
    this.theme = ThemePreference.dark,
    this.logLevel = LogLevelSetting.info,
    this.notificationsEnabled = true,
    this.useSystemCertificates = true,
  });

  final String downloadDirectory;
  final DownloadMode defaultMode;
  final VideoQuality defaultQuality;
  final ContainerFormat defaultContainer;
  final AudioFormat defaultAudioFormat;
  final AudioQuality defaultAudioQuality;
  final int maxConcurrentDownloads;
  final bool numberPlaylistItems;
  final bool skipCompleted;

  /// Custom executable paths. `null` means automatic detection.
  final String? ytDlpPath;
  final String? ffmpegPath;
  final ThemePreference theme;
  final LogLevelSetting logLevel;
  final bool notificationsEnabled;

  /// Make yt-dlp trust the OS certificate store (needed behind TLS-inspecting
  /// corporate proxies). Verification always stays enabled.
  final bool useSystemCertificates;

  DownloadOptions defaultOptions() => DownloadOptions(
        destinationDir: downloadDirectory,
        mode: defaultMode,
        quality: defaultQuality,
        container: defaultContainer,
        audioFormat: defaultAudioFormat,
        audioQuality: defaultAudioQuality,
        numberPlaylistItems: numberPlaylistItems,
      );

  AppSettings copyWith({
    String? downloadDirectory,
    DownloadMode? defaultMode,
    VideoQuality? defaultQuality,
    ContainerFormat? defaultContainer,
    AudioFormat? defaultAudioFormat,
    AudioQuality? defaultAudioQuality,
    int? maxConcurrentDownloads,
    bool? numberPlaylistItems,
    bool? skipCompleted,
    String? Function()? ytDlpPath,
    String? Function()? ffmpegPath,
    ThemePreference? theme,
    LogLevelSetting? logLevel,
    bool? notificationsEnabled,
    bool? useSystemCertificates,
  }) =>
      AppSettings(
        downloadDirectory: downloadDirectory ?? this.downloadDirectory,
        defaultMode: defaultMode ?? this.defaultMode,
        defaultQuality: defaultQuality ?? this.defaultQuality,
        defaultContainer: defaultContainer ?? this.defaultContainer,
        defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
        defaultAudioQuality: defaultAudioQuality ?? this.defaultAudioQuality,
        maxConcurrentDownloads: (maxConcurrentDownloads ?? this.maxConcurrentDownloads)
            .clamp(1, AppConfig.maxConcurrentLimit),
        numberPlaylistItems: numberPlaylistItems ?? this.numberPlaylistItems,
        skipCompleted: skipCompleted ?? this.skipCompleted,
        ytDlpPath: ytDlpPath != null ? ytDlpPath() : this.ytDlpPath,
        ffmpegPath: ffmpegPath != null ? ffmpegPath() : this.ffmpegPath,
        theme: theme ?? this.theme,
        logLevel: logLevel ?? this.logLevel,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        useSystemCertificates: useSystemCertificates ?? this.useSystemCertificates,
      );

  Map<String, Object?> toJson() => {
        'downloadDirectory': downloadDirectory,
        'defaultMode': defaultMode.name,
        'defaultQuality': defaultQuality.name,
        'defaultContainer': defaultContainer.name,
        'defaultAudioFormat': defaultAudioFormat.name,
        'defaultAudioQuality': defaultAudioQuality.name,
        'maxConcurrentDownloads': maxConcurrentDownloads,
        'numberPlaylistItems': numberPlaylistItems,
        'skipCompleted': skipCompleted,
        'ytDlpPath': ytDlpPath,
        'ffmpegPath': ffmpegPath,
        'theme': theme.name,
        'logLevel': logLevel.name,
        'notificationsEnabled': notificationsEnabled,
        'useSystemCertificates': useSystemCertificates,
      };

  /// Tolerant parsing: unknown or malformed values fall back to defaults.
  factory AppSettings.fromJson(Map<String, Object?> json, {required String fallbackDirectory}) {
    String? str(String k) {
      final v = json[k];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    bool flag(String k, bool d) => json[k] is bool ? json[k] as bool : d;
    final concurrency = json['maxConcurrentDownloads'];
    return AppSettings(
      downloadDirectory: str('downloadDirectory') ?? fallbackDirectory,
      defaultMode: DownloadMode.fromName(str('defaultMode')),
      defaultQuality: VideoQuality.fromName(str('defaultQuality')),
      defaultContainer: ContainerFormat.fromName(str('defaultContainer')),
      defaultAudioFormat: AudioFormat.fromName(str('defaultAudioFormat')),
      defaultAudioQuality: AudioQuality.fromName(str('defaultAudioQuality')),
      maxConcurrentDownloads: concurrency is int
          ? concurrency.clamp(1, AppConfig.maxConcurrentLimit)
          : 2,
      numberPlaylistItems: flag('numberPlaylistItems', true),
      skipCompleted: flag('skipCompleted', true),
      ytDlpPath: str('ytDlpPath'),
      ffmpegPath: str('ffmpegPath'),
      theme: ThemePreference.fromName(str('theme')),
      logLevel: LogLevelSetting.values.firstWhere(
        (l) => l.name == str('logLevel'),
        orElse: () => LogLevelSetting.info,
      ),
      notificationsEnabled: flag('notificationsEnabled', true),
      useSystemCertificates: flag('useSystemCertificates', true),
    );
  }
}
