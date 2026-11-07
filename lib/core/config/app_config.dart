/// Static application configuration.
abstract final class AppConfig {
  static const appName = 'CourseGrab';
  static const version = '1.0.0';
  static const buildNumber = 1;
  static const dataFolderName = 'CourseGrab';
  static const databaseFileName = 'coursegrab.db';

  /// Hard upper bound for user-configurable concurrency.
  static const maxConcurrentLimit = 6;

  /// Timeout used when probing executables (`--version`).
  static const probeTimeout = Duration(seconds: 20);

  /// yt-dlp's first launch after installation can take ~30 s on macOS while
  /// the system scans the new binaries.
  static const firstLaunchProbeTimeout = Duration(seconds: 120);

  /// Timeout used for metadata extraction of a URL.
  static const metadataTimeout = Duration(minutes: 3);

  /// Grace period between a polite interrupt and a forced kill.
  static const processKillGrace = Duration(seconds: 4);
}

/// Official release endpoints for dependencies that CourseGrab can install.
///
/// Every download is verified against the SHA-256 sums published in the same
/// release before it is made executable.
abstract final class DependencySources {
  static const ytDlpReleaseBase =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download';
  static const ytDlpChecksums = '$ytDlpReleaseBase/SHA2-256SUMS';
  // Official "onedir" builds: an executable plus `_internal/`. They start in
  // well under a second, unlike the single-file builds which unpack (and get
  // re-scanned by the OS) on every launch.
  static const ytDlpMacAsset = 'yt-dlp_macos.zip';
  static const ytDlpMacFolder = 'yt-dlp_macos';
  static const ytDlpMacExecutable = 'yt-dlp_macos';
  static const ytDlpWindowsX64Asset = 'yt-dlp_win.zip';
  static const ytDlpWindowsArm64Asset = 'yt-dlp_win_arm64.zip';
  static const ytDlpWindowsFolder = 'yt-dlp';
  static const ytDlpWindowsExecutable = 'yt-dlp.exe';

  static const ffmpegReleaseBase =
      'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest';
  static const ffmpegChecksums = '$ffmpegReleaseBase/checksums.sha256';
  static const ffmpegWindowsX64Asset = 'ffmpeg-master-latest-win64-gpl.zip';
  static const ffmpegWindowsArm64Asset =
      'ffmpeg-master-latest-winarm64-gpl.zip';

  static const ytDlpHomepage = 'https://github.com/yt-dlp/yt-dlp';
  static const ffmpegHomepage = 'https://ffmpeg.org/download.html';
}
