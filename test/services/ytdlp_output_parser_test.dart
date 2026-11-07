import 'package:coursegrab/services/ytdlp/ytdlp_output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YtDlpOutputParser', () {
    test('parses a progress line with totals', () {
      final e = YtDlpOutputParser.parse(
          '[cg]dl|downloading|1048576|10485760|NA|524288.5|17|NA|NA|137') as ProgressEvent;
      expect(e.status, 'downloading');
      expect(e.downloadedBytes, 1048576);
      expect(e.totalBytes, 10485760);
      expect(e.totalBytesEstimate, isNull);
      expect(e.speed, closeTo(524288.5, 0.01));
      expect(e.eta, 17);
      expect(e.formatId, '137');
    });

    test('parses fragment progress with estimated total', () {
      final e = YtDlpOutputParser.parse(
          '[cg]dl|downloading|2000|NA|50000.0|1000|NA|3|20|hls-720') as ProgressEvent;
      expect(e.totalBytes, isNull);
      expect(e.totalBytesEstimate, 50000);
      expect(e.fragmentIndex, 3);
      expect(e.fragmentCount, 20);
      expect(e.eta, isNull);
    });

    test('treats NA / None as null', () {
      final e = YtDlpOutputParser.parse('[cg]dl|downloading|NA|None|NA|NA|NA|NA|NA|NA') as ProgressEvent;
      expect(e.downloadedBytes, isNull);
      expect(e.totalBytes, isNull);
      expect(e.speed, isNull);
      expect(e.formatId, isNull);
    });

    test('tolerates leading whitespace / prefixes before the marker', () {
      final e = YtDlpOutputParser.parse('  [cg]dl|finished|10|10|NA|NA|NA|NA|NA|140');
      expect(e, isA<ProgressEvent>());
      expect((e as ProgressEvent).status, 'finished');
    });

    test('parses post-processing events', () {
      final e = YtDlpOutputParser.parse('[cg]pp|started|Merger') as PostProcessEvent;
      expect(e.status, 'started');
      expect(e.postprocessor, 'Merger');
      expect(e.label, 'Merging audio and video');
    });

    test('file path keeps pipe characters', () {
      final e = YtDlpOutputParser.parse('[cg]file|/out/a|b [id].mp4') as FileEvent;
      expect(e.path, '/out/a|b [id].mp4');
    });

    test('parses final metadata and computes short-side resolution', () {
      final e = YtDlpOutputParser.parse('[cg]meta|1920|1080|mp4') as MetaEvent;
      expect(e.height, 1920);
      expect(e.width, 1080);
      expect(e.res, 1080);
      expect(e.ext, 'mp4');
    });

    test('classifies plain errors and warnings', () {
      final err = YtDlpOutputParser.parse('ERROR: [youtube] x: Private video') as LogLineEvent;
      expect(err.isError, isTrue);
      final warn = YtDlpOutputParser.parse('WARNING: something') as LogLineEvent;
      expect(warn.isWarning, isTrue);
      final other = YtDlpOutputParser.parse('[info] something') as LogLineEvent;
      expect(other.isError || other.isWarning, isFalse);
    });

    test('unknown marker types fall back to log lines', () {
      expect(YtDlpOutputParser.parse('[cg]zzz|1'), isA<LogLineEvent>());
      expect(YtDlpOutputParser.parse('[cg]nopipe'), isA<LogLineEvent>());
    });
  });
}
