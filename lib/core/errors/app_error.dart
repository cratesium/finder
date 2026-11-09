/// Categories of failure that finder knows how to explain to users.
enum AppErrorKind {
  invalidUrl,
  unsupportedSource,
  missingDependency,
  network,
  certificate,
  unavailable,
  inaccessible,
  drmProtected,
  formatUnavailable,
  ffmpeg,
  diskFull,
  permission,
  processCrashed,
  interrupted,
  storage,
  timeout,
  cancelled,
  unknown,
}

/// A user-presentable error.
///
/// [message] is safe to show in the UI. [detail] holds diagnostic text that is
/// written to logs but never shown verbatim as a stack trace.
class AppError implements Exception {
  const AppError(this.kind, this.message, {this.detail});

  factory AppError.of(AppErrorKind kind, {String? detail}) =>
      AppError(kind, defaultMessage(kind), detail: detail);

  final AppErrorKind kind;
  final String message;
  final String? detail;

  String get title => switch (kind) {
        AppErrorKind.invalidUrl => 'Invalid link',
        AppErrorKind.unsupportedSource => 'Unsupported source',
        AppErrorKind.missingDependency => 'Missing dependency',
        AppErrorKind.network => 'Network problem',
        AppErrorKind.certificate => 'Secure connection failed',
        AppErrorKind.unavailable => 'Video unavailable',
        AppErrorKind.inaccessible => 'Access restricted',
        AppErrorKind.drmProtected => 'DRM protected',
        AppErrorKind.formatUnavailable => 'Format unavailable',
        AppErrorKind.ffmpeg => 'FFmpeg failed',
        AppErrorKind.diskFull => 'Disk full',
        AppErrorKind.permission => 'Permission denied',
        AppErrorKind.processCrashed => 'Downloader crashed',
        AppErrorKind.interrupted => 'Interrupted',
        AppErrorKind.storage => 'Storage error',
        AppErrorKind.timeout => 'Timed out',
        AppErrorKind.cancelled => 'Cancelled',
        AppErrorKind.unknown => 'Something went wrong',
      };

  static String defaultMessage(AppErrorKind kind) => switch (kind) {
        AppErrorKind.invalidUrl =>
          'That doesn\'t look like a valid http(s) link. Check it and try again.',
        AppErrorKind.unsupportedSource =>
          'This website or link type isn\'t supported by yt-dlp.',
        AppErrorKind.missingDependency =>
          'A required tool is missing. Open Settings → Dependencies to set it up.',
        AppErrorKind.network =>
          'Couldn\'t reach the server. Check your internet connection and try again.',
        AppErrorKind.certificate =>
          'The secure connection couldn\'t be verified. If your network inspects HTTPS traffic, enable '
              'Settings → Network → Use system certificates.',
        AppErrorKind.unavailable =>
          'This video is unavailable. It may have been removed or blocked in your region.',
        AppErrorKind.inaccessible =>
          'This content is private or requires signing in. finder only downloads content you can access without bypassing restrictions.',
        AppErrorKind.drmProtected =>
          'This content is DRM protected and can\'t be downloaded.',
        AppErrorKind.formatUnavailable =>
          'The requested format isn\'t available for this video. Try a different quality or container.',
        AppErrorKind.ffmpeg =>
          'FFmpeg couldn\'t process the downloaded streams. Check your FFmpeg installation in Settings.',
        AppErrorKind.diskFull =>
          'There isn\'t enough free disk space at the destination.',
        AppErrorKind.permission =>
          'finder doesn\'t have permission to write to the destination folder.',
        AppErrorKind.processCrashed =>
          'The downloader stopped unexpectedly. See the logs for details.',
        AppErrorKind.interrupted =>
          'The download was interrupted before it finished.',
        AppErrorKind.storage =>
          'finder couldn\'t read or write its local database.',
        AppErrorKind.timeout => 'The operation took too long and was stopped.',
        AppErrorKind.cancelled => 'The operation was cancelled.',
        AppErrorKind.unknown =>
          'An unexpected error occurred. See the logs for details.',
      };

  /// Whether retrying without changes has a reasonable chance of success.
  bool get isRetryable => switch (kind) {
        AppErrorKind.network ||
        AppErrorKind.certificate ||
        AppErrorKind.processCrashed ||
        AppErrorKind.interrupted ||
        AppErrorKind.timeout ||
        AppErrorKind.cancelled ||
        AppErrorKind.unknown ||
        AppErrorKind.ffmpeg ||
        AppErrorKind.diskFull ||
        AppErrorKind.permission ||
        AppErrorKind.missingDependency ||
        AppErrorKind.storage =>
          true,
        _ => false,
      };

  @override
  String toString() => 'AppError($kind): $message${detail == null ? '' : ' [$detail]'}';
}
