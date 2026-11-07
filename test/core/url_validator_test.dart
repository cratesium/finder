import 'package:coursegrab/core/utils/url_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlValidator', () {
    test('accepts https video and playlist links', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/playlist?list=PL123',
        'http://example.com/video.mp4',
        'https://vimeo.com/123456',
        'https://localhost:8080/v',
        'https://192.168.1.10/media',
      ]) {
        expect(UrlValidator.validate(url), isA<ValidUrl>(), reason: url);
      }
    });

    test('adds https:// when the scheme is missing', () {
      final r = UrlValidator.validate('youtube.com/watch?v=abc') as ValidUrl;
      expect(r.normalized, 'https://youtube.com/watch?v=abc');
    });

    test('trims surrounding whitespace', () {
      final r = UrlValidator.validate('  https://example.com/a  ') as ValidUrl;
      expect(r.normalized, 'https://example.com/a');
    });

    test('rejects empty input', () {
      expect(UrlValidator.validate(''), isA<InvalidUrl>());
      expect(UrlValidator.validate('   '), isA<InvalidUrl>());
      expect(UrlValidator.validate(null), isA<InvalidUrl>());
    });

    test('rejects non-http schemes', () {
      for (final url in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'ftp://example.com/x',
        'data:text/html,hi',
        'smb://server/share',
      ]) {
        expect(UrlValidator.validate(url), isA<InvalidUrl>(), reason: url);
      }
    });

    test('rejects values that could be parsed as command-line options', () {
      expect(UrlValidator.validate('--exec rm -rf /'), isA<InvalidUrl>());
      expect(UrlValidator.validate('-o/tmp/x'), isA<InvalidUrl>());
    });

    test('rejects whitespace, control characters and embedded credentials', () {
      expect(UrlValidator.validate('https://exa mple.com'), isA<InvalidUrl>());
      expect(UrlValidator.validate('https://example.com/\nfoo'), isA<InvalidUrl>());
      expect(UrlValidator.validate('https://user:pass@example.com/v'), isA<InvalidUrl>());
    });

    test('rejects invalid hosts', () {
      expect(UrlValidator.validate('https://nohost'), isA<InvalidUrl>());
      expect(UrlValidator.validate('https://-bad-.com'), isA<InvalidUrl>());
      expect(UrlValidator.validate('https://999.1.1.1/x'), isA<InvalidUrl>());
      expect(UrlValidator.validate('https://'), isA<InvalidUrl>());
    });

    test('rejects overly long input', () {
      final long = 'https://example.com/${'a' * 3000}';
      expect(UrlValidator.validate(long), isA<InvalidUrl>());
    });

    test('playlist heuristic', () {
      expect(UrlValidator.looksLikePlaylist(Uri.parse('https://youtube.com/playlist?list=PL1')), isTrue);
      expect(UrlValidator.looksLikePlaylist(Uri.parse('https://youtube.com/watch?v=x')), isFalse);
    });
  });
}
