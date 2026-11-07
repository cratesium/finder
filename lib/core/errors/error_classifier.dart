import 'app_error.dart';

/// Maps yt-dlp / FFmpeg diagnostic output to a typed [AppError].
abstract final class ErrorClassifier {
  static final List<(RegExp, AppErrorKind)> _rules = [
    (RegExp(r'DRM', caseSensitive: true), AppErrorKind.drmProtected),
    (RegExp(r'CERTIFICATE_VERIFY_FAILED|certificate verify failed', caseSensitive: false),
        AppErrorKind.certificate),
    (
      RegExp(r'No space left on device|Errno 28|ENOSPC|disk is full',
          caseSensitive: false),
      AppErrorKind.diskFull
    ),
    (
      RegExp(r'Permission denied|Errno 13|Operation not permitted|Access is denied',
          caseSensitive: false),
      AppErrorKind.permission
    ),
    (
      RegExp(
          r'ffmpeg not found|ffprobe and ffmpeg not found|ffmpeg is not installed|'
          r'merging of multiple formats but ffmpeg',
          caseSensitive: false),
      AppErrorKind.missingDependency
    ),
    (
      RegExp(r'Postprocessing:|Conversion failed|ffmpeg exited with code|Error opening output',
          caseSensitive: false),
      AppErrorKind.ffmpeg
    ),
    (
      RegExp(r'Requested format is not available|requested format not available',
          caseSensitive: false),
      AppErrorKind.formatUnavailable
    ),
    (RegExp(r'Unsupported URL', caseSensitive: false), AppErrorKind.unsupportedSource),
    (
      RegExp(
          r'Private video|This video is private|Sign in to confirm|members[- ]only|'
          r'available to this channel.s members|login required|requires authentication|'
          r'account cookies|HTTP Error 401|HTTP Error 403|use --cookies|age-restricted|'
          r'Join this channel',
          caseSensitive: false),
      AppErrorKind.inaccessible
    ),
    (
      RegExp(
          r'Video unavailable|This video is not available|has been removed|'
          r'This video has been terminated|is not available in your country|'
          r'HTTP Error 404|does not exist|Premieres in',
          caseSensitive: false),
      AppErrorKind.unavailable
    ),
    (
      RegExp(
          r'Unable to download webpage|getaddrinfo|Name or service not known|'
          r'nodename nor servname|timed out|Connection reset|Connection refused|'
          r'urlopen error|Temporary failure in name resolution|Network is unreachable|'
          r'Failed to resolve|IncompleteRead|Unable to download API page|'
          r'HTTP Error 5\d\d|ConnectionError|RemoteDisconnected',
          caseSensitive: false),
      AppErrorKind.network
    ),
  ];

  /// Classifies [output] (typically stderr). Returns [AppErrorKind.unknown]
  /// when nothing matches.
  static AppErrorKind classifyKind(String output) {
    for (final (pattern, kind) in _rules) {
      if (pattern.hasMatch(output)) return kind;
    }
    return AppErrorKind.unknown;
  }

  /// Builds an [AppError] from process output. The most relevant `ERROR:`
  /// line is kept as [AppError.detail].
  static AppError fromProcessOutput(String stderr, {int? exitCode}) {
    final errorLine = lastErrorLine(stderr);
    final haystack = errorLine ?? stderr;
    var kind = classifyKind(haystack);
    if (kind == AppErrorKind.unknown && errorLine != null) {
      kind = classifyKind(stderr);
    }
    if (kind == AppErrorKind.unknown && exitCode != null && exitCode < 0) {
      kind = AppErrorKind.processCrashed;
    }
    final detail = [
      if (exitCode != null) 'exit code $exitCode',
      ?errorLine,
    ].join(': ');
    return AppError.of(kind, detail: detail.isEmpty ? null : detail);
  }

  /// Returns the last line beginning with `ERROR:` (yt-dlp convention).
  static String? lastErrorLine(String output) {
    final lines = output.split(RegExp(r'\r?\n'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.startsWith('ERROR:')) {
        return line.substring(6).trim();
      }
    }
    return null;
  }
}
