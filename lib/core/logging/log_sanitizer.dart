import 'dart:io';

/// Removes sensitive information from text before it is logged or displayed.
///
/// * The user's home directory is replaced with `~`.
/// * Values of credential-like URL query parameters are redacted.
abstract final class LogSanitizer {
  static String? _home = _detectHome();

  static String? _detectHome() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    return (home == null || home.isEmpty) ? null : home;
  }

  /// Overrides the detected home directory (used by tests).
  static set homeOverride(String? value) => _home = value;

  static final _secretParam = RegExp(
    r'([?&](?:token|access_token|auth|key|api_key|apikey|sig|signature|password|pass|session|sessionid|cookie)=)[^&\s]+',
    caseSensitive: false,
  );

  static String sanitize(String input) {
    var out = input;
    final home = _home;
    if (home != null && home.length > 1) {
      out = out.replaceAll(home, '~');
      if (Platform.isWindows) {
        out = out.replaceAll(home.replaceAll('\\', '/'), '~');
      }
    }
    out = out.replaceAllMapped(_secretParam, (m) => '${m.group(1)}<redacted>');
    return out;
  }
}
