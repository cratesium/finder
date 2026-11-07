/// Result of validating a user supplied URL.
sealed class UrlValidation {
  const UrlValidation();
}

class ValidUrl extends UrlValidation {
  const ValidUrl(this.uri);
  final Uri uri;
  String get normalized => uri.toString();
}

class InvalidUrl extends UrlValidation {
  const InvalidUrl(this.reason);
  final String reason;
}

/// Validates and normalizes media URLs before they reach any process.
///
/// Only absolute `http`/`https` URLs with a plausible host are accepted. This
/// also guarantees the value can never be mistaken for a command-line option.
abstract final class UrlValidator {
  static const maxLength = 2048;
  static final _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final _hostLabel = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

  static UrlValidation validate(String? raw) {
    final input = (raw ?? '').trim();
    if (input.isEmpty) return const InvalidUrl('Enter a video or playlist link.');
    if (input.length > maxLength) {
      return const InvalidUrl('That link is too long to be a valid URL.');
    }
    if (_controlChars.hasMatch(input) || input.contains(RegExp(r'\s'))) {
      return const InvalidUrl('Links can\'t contain spaces or line breaks.');
    }

    var candidate = input;
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(candidate);
    if (!hasScheme) {
      if (candidate.startsWith('//')) {
        candidate = 'https:$candidate';
      } else if (RegExp(r'^[a-zA-Z0-9]').hasMatch(candidate)) {
        candidate = 'https://$candidate';
      } else {
        return const InvalidUrl('That doesn\'t look like a web link.');
      }
    }

    final Uri uri;
    try {
      uri = Uri.parse(candidate);
    } on FormatException {
      return const InvalidUrl('That link couldn\'t be parsed.');
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const InvalidUrl('Only http:// and https:// links are supported.');
    }
    if (uri.userInfo.isNotEmpty) {
      return const InvalidUrl(
          'Links with embedded usernames or passwords aren\'t supported.');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return const InvalidUrl('The link is missing a website address.');
    if (!_isValidHost(host)) {
      return const InvalidUrl('The website address in this link isn\'t valid.');
    }
    return ValidUrl(uri.replace(scheme: scheme));
  }

  static bool _isValidHost(String host) {
    if (host == 'localhost') return true;
    // IPv4
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (ipv4 != null) {
      return List.generate(4, (i) => int.parse(ipv4.group(i + 1)!)).every((o) => o <= 255);
    }
    if (host.startsWith('[') || host.contains(':')) return true; // IPv6 parsed by Uri
    if (!host.contains('.')) return false;
    final labels = host.split('.');
    if (labels.any((l) => l.isEmpty || l.length > 63)) return false;
    // Allow punycode / unicode hosts; validate ASCII labels strictly.
    for (final l in labels) {
      if (RegExp(r'^[\x00-\x7F]+$').hasMatch(l) && !_hostLabel.hasMatch(l)) {
        return false;
      }
    }
    return RegExp(r'[a-z]', caseSensitive: false).hasMatch(labels.last) ||
        labels.last.length >= 2;
  }

  /// Heuristic used only for UI hints; yt-dlp decides the real type.
  static bool looksLikePlaylist(Uri uri) {
    final q = uri.queryParameters;
    return q.containsKey('list') ||
        uri.path.contains('/playlist') ||
        uri.path.contains('/channel/') ||
        uri.path.startsWith('/@');
  }
}
