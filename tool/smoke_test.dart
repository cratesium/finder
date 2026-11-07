// Real end-to-end smoke test against the official yt-dlp release.
//
//   dart run tool/smoke_test.dart <work-dir> [url]
//
// 1. Installs yt-dlp via CourseGrab's DependencyManager (SHA-256 verified).
// 2. Extracts metadata with YtDlpMetadataService.
// 3. Downloads with YtDlpDownloaderService using CourseGrab's exact argument
//    builder and prints the parsed progress events.
//
// If FFmpeg is resolvable it is used; otherwise a single-file format is
// requested so the test can run without FFmpeg. Set SMOKE_REAL_ARGS=1 to
// always use CourseGrab's unmodified argument list.
import 'dart:io';

import 'package:coursegrab/core/utils/platform_info.dart';
import 'package:coursegrab/models/dependency_status.dart';
import 'package:coursegrab/models/download_options.dart';
import 'package:coursegrab/services/dependency_manager.dart';
import 'package:coursegrab/services/downloader_service.dart';
import 'package:coursegrab/services/metadata_service.dart';
import 'package:coursegrab/services/process_service.dart';
import 'package:coursegrab/services/trust_store_service.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_args.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_output_parser.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/smoke_test.dart <work-dir> [url]');
    exit(64);
  }
  final work = Directory(args[0])..createSync(recursive: true);
  final url = args.length > 1 ? args[1] : 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  final processes = ProcessService.forHost();
  final deps = DependencyManager(
    platform: PlatformInfo.current(),
    processes: processes,
    managedBinDir: p.join(work.path, 'bin'),
  );

  var yt = await deps.resolve(DependencyKind.ytDlp);
  if (!yt.isReady || yt.source != DependencySource.managed) {
    stdout.writeln('Installing yt-dlp (verified)…');
    yt = await deps.install(DependencyKind.ytDlp, onProgress: (f, stage) {});
  }
  stdout.writeln('yt-dlp ${yt.version} at ${yt.path} (${yt.source?.name})');
  final ff = await deps.resolve(DependencyKind.ffmpeg);
  stdout.writeln('ffmpeg: ${ff.isReady ? '${ff.version} at ${ff.path}' : 'not found'}');

  final network = await TrustStoreService(platform: PlatformInfo.current(), dataDir: work.path)
      .build(useSystemCertificates: true);
  stdout.writeln('network: args=${network.arguments} bundle=${network.caBundlePath != null}');
  final info = await YtDlpMetadataService(processes).fetch(url, ytDlpPath: yt.path!, network: network);
  final e = info.entries.first;
  stdout.writeln('metadata: kind=${info.kind.name} title="${info.title}" entries=${info.totalCount} '
      'duration=${info.totalDuration} maxRes=${e.maxResolution} formats=${e.formats.length} '
      'qualities=${e.availableQualities.map((q) => q.name).toList()}');

  final out = Directory(p.join(work.path, 'out'))..createSync(recursive: true);
  final options = DownloadOptions(destinationDir: out.path, quality: VideoQuality.p360);
  final unmodified = ff.isReady || Platform.environment['SMOKE_REAL_ARGS'] == '1';
  final DownloaderService downloader = unmodified
      ? YtDlpDownloaderService(processes)
      : _SingleFileDownloader(processes);
  final job = await downloader.start(DownloadJobSpec(
    url: e.url,
    options: options,
    directory: out.path,
    outputTemplate: YtDlpArgs.outputTemplate(),
    ytDlpPath: yt.path!,
    ffmpegPath: ff.isReady ? ff.path : null,
    network: network,
  ));
  var progressEvents = 0;
  job.events.listen((ev) {
    switch (ev) {
      case ProgressEvent():
        progressEvents++;
        if (progressEvents <= 3 || ev.status == 'finished') {
          stdout.writeln('  progress ${ev.status} ${ev.downloadedBytes}/${ev.totalBytes ?? ev.totalBytesEstimate} '
              'speed=${ev.speed?.round()} eta=${ev.eta} fmt=${ev.formatId}');
        }
      case PostProcessEvent():
        stdout.writeln('  postprocess ${ev.status} ${ev.postprocessor}');
      case DestinationEvent():
        stdout.writeln('  destination ${p.basename(ev.path)}');
      case LogLineEvent(:final line, :final isError) when isError:
        stdout.writeln('  stderr: $line');
      default:
        break;
    }
  });
  final outcome = await job.outcome;
  stdout.writeln('progress events: $progressEvents');
  switch (outcome) {
    case DownloadSucceeded(:final filePath, :final resolution, :final extension):
      stdout.writeln('SUCCESS ${p.basename(filePath)} ${File(filePath).lengthSync()} bytes res=$resolution ext=$extension');
    case DownloadFailed(:final error):
      stdout.writeln('FAILED ${error.kind.name}: ${error.message} [${error.detail}]');
      exitCode = 1;
    case DownloadStopped():
      stdout.writeln('STOPPED');
      exitCode = 1;
  }
}

/// Uses CourseGrab's full argument list but swaps the format selection for a
/// single pre-merged file, so the run works without FFmpeg.
class _SingleFileDownloader implements DownloaderService {
  _SingleFileDownloader(this._processes);
  final ProcessService _processes;

  @override
  Future<DownloadJob> start(DownloadJobSpec spec) async {
    final real = YtDlpDownloaderService(_ArgRewritingProcessService(_processes));
    return real.start(spec);
  }
}

class _ArgRewritingProcessService extends ProcessService {
  _ArgRewritingProcessService(this._inner);
  final ProcessService _inner;

  @override
  Future<ManagedProcess> start(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) {
    final a = List.of(arguments);
    final f = a.indexOf('-f');
    a[f + 1] = 'b';
    for (final flag in ['--merge-output-format', '--remux-video']) {
      final i = a.indexOf(flag);
      if (i >= 0) a.removeRange(i, i + 2);
    }
    stdout.writeln('  (no ffmpeg: using single-file format "b")');
    return _inner.start(executable, a, workingDirectory: workingDirectory, environment: environment);
  }
}
