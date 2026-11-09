import 'package:finder/models/download_options.dart';
import 'package:finder/services/ytdlp/ytdlp_args.dart';
import 'package:flutter_test/flutter_test.dart';

String? valueAfter(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

void main() {
  const base = DownloadOptions(destinationDir: '/out');

  group('format selection', () {
    test('best quality MP4 merges best video+audio and prefers mp4/m4a', () {
      final a = YtDlpArgs.formatSelection(base);
      expect(valueAfter(a, '-f'), 'bv*+ba/b');
      expect(valueAfter(a, '-S'), 'ext:mp4:m4a');
      expect(valueAfter(a, '--merge-output-format'), 'mp4');
      expect(valueAfter(a, '--remux-video'), 'mp4');
      expect(a, isNot(contains('--recode-video')));
    });

    test('resolution cap uses res sort (at or below, vertical-safe)', () {
      final a = YtDlpArgs.formatSelection(base.copyWith(quality: VideoQuality.p1080));
      expect(valueAfter(a, '-S'), 'res:1080,ext:mp4:m4a');
    });

    for (final q in VideoQuality.values.where((q) => q.height != null)) {
      test('quality ${q.name} maps to res:${q.height}', () {
        final a = YtDlpArgs.formatSelection(base.copyWith(quality: q, container: ContainerFormat.mkv));
        expect(valueAfter(a, '-S'), 'res:${q.height}');
        expect(valueAfter(a, '--merge-output-format'), 'mkv');
      });
    }

    test('original container does not force a container', () {
      final a = YtDlpArgs.formatSelection(base.copyWith(container: ContainerFormat.original));
      expect(a, isNot(contains('--merge-output-format')));
      expect(a, isNot(contains('--remux-video')));
      expect(a, isNot(contains('-S')));
    });

    test('audio only keeps original audio without re-encoding', () {
      final a = YtDlpArgs.formatSelection(base.copyWith(mode: DownloadMode.audioOnly));
      expect(valueAfter(a, '-f'), 'ba/b');
      expect(a, contains('-x'));
      expect(valueAfter(a, '--audio-format'), 'best');
      expect(a, isNot(contains('--audio-quality')));
    });

    test('MP3 conversion sets format and quality', () {
      final a = YtDlpArgs.formatSelection(base.copyWith(
          mode: DownloadMode.audioOnly, audioFormat: AudioFormat.mp3, audioQuality: AudioQuality.k192));
      expect(valueAfter(a, '--audio-format'), 'mp3');
      expect(valueAfter(a, '--audio-quality'), '192K');
    });
  });

  group('download arguments', () {
    test('URL is passed after -- as the final argument', () {
      final a = YtDlpArgs.download(
        url: 'https://example.com/v?a=1&b=2',
        options: base,
        directory: '/out dir/with spaces',
        outputTemplate: YtDlpArgs.outputTemplate(),
      );
      expect(a.last, 'https://example.com/v?a=1&b=2');
      expect(a[a.length - 2], '--');
      expect(valueAfter(a, '-P'), 'home:/out dir/with spaces');
    });

    test('ignores user config and emits machine-readable progress', () {
      final a = YtDlpArgs.download(
        url: 'https://example.com/v',
        options: base,
        directory: '/out',
        outputTemplate: 'x',
        ffmpegLocation: '/opt/ffmpeg',
      );
      expect(a.first, '--ignore-config');
      expect(a, containsAll(['--newline', '--no-playlist', '--progress', '--quiet']));
      expect(valueAfter(a, '--ffmpeg-location'), '/opt/ffmpeg');
      expect(a.where((x) => x.startsWith('download:${YtDlpArgs.marker}dl|')), hasLength(1));
      expect(a.where((x) => x.startsWith('postprocess:${YtDlpArgs.marker}pp|')), hasLength(1));
      expect(a.where((x) => x.startsWith('after_move:${YtDlpArgs.marker}file|')), hasLength(1));
    });

    test('metadata extraction never downloads and ends with the URL', () {
      final a = YtDlpArgs.metadata('https://example.com/p');
      expect(a, containsAll(['--dump-single-json', '--flat-playlist', '--ignore-config']));
      expect(a.sublist(a.length - 2), ['--', 'https://example.com/p']);
    });
  });

  group('output template', () {
    test('numbered playlist items are zero padded', () {
      expect(YtDlpArgs.outputTemplate(playlistIndex: 7, numbered: true),
          '007 - %(title).180B [%(id)s].%(ext)s');
    });

    test('unnumbered omits the prefix', () {
      expect(YtDlpArgs.outputTemplate(playlistIndex: 7), '%(title).180B [%(id)s].%(ext)s');
    });
  });
}
