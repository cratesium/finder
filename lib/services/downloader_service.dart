import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../core/errors/app_error.dart';
import '../core/errors/error_classifier.dart';
import '../models/download_options.dart';
import 'process_service.dart';
import 'trust_store_service.dart';
import 'ytdlp/ytdlp_args.dart';
import 'ytdlp/ytdlp_output_parser.dart';

final _log = Logger('downloader');

/// Everything the downloader needs for one item.
class DownloadJobSpec {
  const DownloadJobSpec({
    required this.url,
    required this.options,
    required this.directory,
    required this.outputTemplate,
    required this.ytDlpPath,
    this.ffmpegPath,
    this.network = YtDlpNetworkConfig.none,
  });

  final String url;
  final DownloadOptions options;
  final String directory;
  final String outputTemplate;
  final String ytDlpPath;
  final String? ffmpegPath;
  final YtDlpNetworkConfig network;
}

sealed class DownloadOutcome {
  const DownloadOutcome();
}

class DownloadSucceeded extends DownloadOutcome {
  const DownloadSucceeded({required this.filePath, this.resolution, this.extension});
  final String filePath;
  final int? resolution;
  final String? extension;
}

class DownloadFailed extends DownloadOutcome {
  const DownloadFailed(this.error);
  final AppError error;
}

/// The process was stopped on request (pause or cancel).
class DownloadStopped extends DownloadOutcome {
  const DownloadStopped();
}

/// A running download.
abstract interface class DownloadJob {
  Stream<YtDlpEvent> get events;
  Future<DownloadOutcome> get outcome;

  /// Stops the job. Partial data stays on disk so it can be resumed.
  Future<void> stop();

  /// Paths of partial / intermediate files yt-dlp announced for this job.
  List<String> get announcedDestinations;
}

abstract interface class DownloaderService {
  Future<DownloadJob> start(DownloadJobSpec spec);
}

class YtDlpDownloaderService implements DownloaderService {
  YtDlpDownloaderService(this._processes);

  final ProcessService _processes;

  @override
  Future<DownloadJob> start(DownloadJobSpec spec) async {
    final args = YtDlpArgs.download(
      url: spec.url,
      options: spec.options,
      directory: spec.directory,
      outputTemplate: spec.outputTemplate,
      ffmpegLocation: spec.ffmpegPath,
      network: spec.network.arguments,
    );
    final ManagedProcess proc;
    try {
      proc = await _processes.start(
        spec.ytDlpPath,
        args,
        workingDirectory: spec.directory,
        environment: spec.network.environment,
      );
    } on ProcessException catch (e) {
      throw AppError.of(AppErrorKind.missingDependency, detail: 'cannot start yt-dlp: ${e.message}');
    }
    _log.info('started download pid=${proc.pid} url=${spec.url}');
    return _YtDlpJob(proc);
  }
}

class _YtDlpJob implements DownloadJob {
  _YtDlpJob(this._proc) {
    // Completion is tracked from the start: asFuture() on an already finished
    // subscription would never complete.
    _proc.stdoutLines.listen(_onLine, onDone: _stdoutDone.complete);
    _proc.stderrLines.listen((line) {
      _stderrTail.add(line);
      if (_stderrTail.length > 60) _stderrTail.removeAt(0);
      _onLine(line);
    }, onDone: _stderrDone.complete);
    _outcome = _run();
  }

  final ManagedProcess _proc;
  final _events = StreamController<YtDlpEvent>.broadcast();
  final _stderrTail = <String>[];
  final _destinations = <String>[];
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  late final Future<DownloadOutcome> _outcome;
  String? _finalPath;
  MetaEvent? _meta;
  bool _stopRequested = false;

  @override
  Stream<YtDlpEvent> get events => _events.stream;

  @override
  Future<DownloadOutcome> get outcome => _outcome;

  @override
  List<String> get announcedDestinations => List.unmodifiable(_destinations);

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final event = YtDlpOutputParser.parse(line);
    switch (event) {
      case FileEvent(:final path):
        _finalPath = path;
      case MetaEvent():
        _meta = event;
      case DestinationEvent(:final path):
        _destinations.add(path);
      case LogLineEvent(:final line, :final isError, :final isWarning):
        if (isError) {
          _log.warning(line);
        } else if (isWarning) {
          _log.info(line);
        } else {
          _log.finer(line);
        }
      default:
        break;
    }
    if (!_events.isClosed) _events.add(event);
  }

  Future<DownloadOutcome> _run() async {
    final code = await _proc.exitCode;
    // Drain remaining output before deciding the outcome.
    await Future.wait([_stdoutDone.future, _stderrDone.future])
        .timeout(const Duration(seconds: 3), onTimeout: () => const []);
    await _events.close();

    if (_stopRequested) return const DownloadStopped();

    if (code == 0) {
      final path = _finalPath;
      if (path == null) {
        return DownloadFailed(AppError(AppErrorKind.unknown,
            'The download finished but no output file was reported.',
            detail: 'exit 0 without filepath; stderr: ${_stderrTail.join(' | ')}'));
      }
      if (!await File(path).exists()) {
        return DownloadFailed(AppError(AppErrorKind.unknown,
            'The download finished but the output file is missing.',
            detail: 'missing ${p.basename(path)}'));
      }
      return DownloadSucceeded(filePath: path, resolution: _meta?.res, extension: _meta?.ext);
    }
    final err = ErrorClassifier.fromProcessOutput(_stderrTail.join('\n'), exitCode: code);
    _log.warning('download failed (exit $code): ${err.detail}');
    return DownloadFailed(err);
  }

  @override
  Future<void> stop() async {
    if (_stopRequested) return;
    _stopRequested = true;
    await _proc.terminate();
  }
}
