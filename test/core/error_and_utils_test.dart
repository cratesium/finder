import 'package:coursegrab/core/errors/app_error.dart';
import 'package:coursegrab/core/errors/error_classifier.dart';
import 'package:coursegrab/core/logging/log_sanitizer.dart';
import 'package:coursegrab/core/utils/formatters.dart';
import 'package:coursegrab/core/utils/path_utils.dart';
import 'package:coursegrab/models/app_settings.dart';
import 'package:coursegrab/models/download_options.dart';
import 'package:coursegrab/services/binary_installer.dart';
import 'package:coursegrab/services/ffmpeg_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorClassifier', () {
    final cases = <String, AppErrorKind>{
      'ERROR: [youtube] abc: Private video. Sign in if you\'ve been granted access': AppErrorKind.inaccessible,
      'ERROR: [youtube] abc: Sign in to confirm your age': AppErrorKind.inaccessible,
      'ERROR: [youtube] abc: Video unavailable': AppErrorKind.unavailable,
      'ERROR: Unsupported URL: https://example.com/': AppErrorKind.unsupportedSource,
      'ERROR: [generic] Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided>':
          AppErrorKind.network,
      'ERROR: unable to write data: [Errno 28] No space left on device': AppErrorKind.diskFull,
      'ERROR: unable to open for writing: [Errno 13] Permission denied': AppErrorKind.permission,
      'ERROR: You have requested merging of multiple formats but ffmpeg is not installed':
          AppErrorKind.missingDependency,
      'ERROR: Postprocessing: Conversion failed!': AppErrorKind.ffmpeg,
      'ERROR: [youtube] abc: Requested format is not available': AppErrorKind.formatUnavailable,
      'ERROR: [x] abc: This video is DRM protected': AppErrorKind.drmProtected,
      'ERROR: [youtube] x: Unable to download API page: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate':
          AppErrorKind.certificate,
      'ERROR: something completely different': AppErrorKind.unknown,
    };
    cases.forEach((stderr, kind) {
      test('classifies "$stderr"', () {
        expect(ErrorClassifier.fromProcessOutput(stderr, exitCode: 1).kind, kind);
      });
    });

    test('uses the last ERROR line as detail', () {
      final e = ErrorClassifier.fromProcessOutput('WARNING: a\nERROR: first\nERROR: second', exitCode: 1);
      expect(e.detail, 'exit code 1: second');
      expect(e.message, isNotEmpty);
    });

    test('negative exit codes without a match are crashes', () {
      expect(ErrorClassifier.fromProcessOutput('', exitCode: -9).kind, AppErrorKind.processCrashed);
    });

    test('every kind has a title and friendly message', () {
      for (final k in AppErrorKind.values) {
        final e = AppError.of(k);
        expect(e.title, isNotEmpty);
        expect(e.message, isNot(contains('Exception')));
      }
    });
  });

  group('Formatters', () {
    test('bytes', () {
      expect(Fmt.bytes(512), '512 B');
      expect(Fmt.bytes(1536), '1.5 KB');
      expect(Fmt.bytes(10 * 1024 * 1024), '10.0 MB');
      expect(Fmt.bytes(null), '—');
    });
    test('speed / eta / duration', () {
      expect(Fmt.speed(2 * 1024 * 1024), '2.0 MB/s');
      expect(Fmt.speed(0), '—');
      expect(Fmt.eta(75), '1:15 left');
      expect(Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(Fmt.durationLong(const Duration(hours: 3, minutes: 5)), '3 h 05 min');
      expect(Fmt.percent(0.4567), '45.7%');
      expect(Fmt.plural(1, 'video'), '1 video');
      expect(Fmt.plural(3, 'video'), '3 videos');
    });
  });

  group('PathUtils', () {
    test('sanitizes illegal characters for every OS', () {
      expect(PathUtils.sanitizeSegment('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(PathUtils.sanitizeSegment('  ..trailing.. '), 'trailing');
      expect(PathUtils.sanitizeSegment(''), 'Untitled');
      expect(PathUtils.sanitizeSegment('CON'), '_CON');
      expect(PathUtils.sanitizeSegment('x' * 300).length, 120);
    });
    test('escapes yt-dlp template markers', () {
      expect(PathUtils.escapeTemplate('100% (done)'), '100%% (done)');
    });
  });

  group('LogSanitizer', () {
    test('redacts home directory and credential parameters', () {
      LogSanitizer.homeOverride = '/Users/alice';
      final out = LogSanitizer.sanitize('saved /Users/alice/Downloads/x.mp4 from https://e.com/v?token=abc123&id=7');
      expect(out, 'saved ~/Downloads/x.mp4 from https://e.com/v?token=<redacted>&id=7');
    });
  });

  group('AppSettings', () {
    test('round-trips through JSON and tolerates bad values', () {
      const s = AppSettings(
        downloadDirectory: '/d',
        defaultQuality: VideoQuality.p720,
        defaultContainer: ContainerFormat.mkv,
        maxConcurrentDownloads: 4,
        ytDlpPath: '/bin/yt-dlp',
        theme: ThemePreference.light,
      );
      final back = AppSettings.fromJson(s.toJson(), fallbackDirectory: '/f');
      expect(back.toJson(), s.toJson());

      final bad = AppSettings.fromJson({'maxConcurrentDownloads': 99, 'defaultQuality': 'p9999'}, fallbackDirectory: '/f');
      expect(bad.downloadDirectory, '/f');
      expect(bad.maxConcurrentDownloads, 6);
      expect(bad.defaultQuality, VideoQuality.best);
    });
  });

  group('BinaryInstaller.parseChecksums', () {
    test('parses sha256sum formats', () {
      final sums = BinaryInstaller.parseChecksums(
          '${'a' * 64}  yt-dlp_macos\n${'B' * 64} *yt-dlp.exe\ngarbage line\n');
      expect(sums['yt-dlp_macos'], 'a' * 64);
      expect(sums['yt-dlp.exe'], 'b' * 64);
      expect(sums.length, 2);
    });
  });

  group('FfmpegService parsing', () {
    test('parses versions', () {
      expect(FfmpegService.parseVersion('ffmpeg version 7.1.1 Copyright (c) 2000-2025'), '7.1.1');
      expect(FfmpegService.parseVersion('ffmpeg version N-118000-g1234-tessus  https://evermeet.cx'), 'N-118000-g1234');
      expect(FfmpegService.parseVersion('nope'), isNull);
    });
    test('parses ffprobe CSV', () {
      final p = FfmpegService.parseProbe('video,1920,1080\naudio,,\n');
      expect(p.hasVideo, isTrue);
      expect(p.hasAudio, isTrue);
      expect(p.res, 1080);
    });
  });
}
