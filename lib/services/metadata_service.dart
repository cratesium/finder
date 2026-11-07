import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_error.dart';
import '../core/errors/error_classifier.dart';
import '../models/media_info.dart';
import 'cancellation.dart';
import 'process_service.dart';
import 'trust_store_service.dart';
import 'ytdlp/metadata_parser.dart';
import 'ytdlp/ytdlp_args.dart';

final _log = Logger('metadata');

/// Extracts video/playlist metadata without downloading media.
abstract interface class MetadataService {
  Future<MediaInfo> fetch(
    String url, {
    required String ytDlpPath,
    CancellationToken? cancel,
    YtDlpNetworkConfig network = YtDlpNetworkConfig.none,
  });
}

class YtDlpMetadataService implements MetadataService {
  YtDlpMetadataService(this._processes, {this.timeout = AppConfig.metadataTimeout});

  final ProcessService _processes;
  final Duration timeout;

  @override
  Future<MediaInfo> fetch(
    String url, {
    required String ytDlpPath,
    CancellationToken? cancel,
    YtDlpNetworkConfig network = YtDlpNetworkConfig.none,
  }) async {
    _log.info('extracting metadata for $url');
    final ManagedProcess proc;
    try {
      proc = await _processes.start(
        ytDlpPath,
        YtDlpArgs.metadata(url, network: network.arguments),
        environment: network.environment,
      );
    } catch (e) {
      _log.severe('failed to start yt-dlp', e);
      throw AppError.of(AppErrorKind.missingDependency, detail: 'cannot start yt-dlp: $e');
    }

    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = proc.stdoutLines.forEach(out.writeln);
    final errDone = proc.stderrLines.forEach(err.writeln);

    var cancelled = false;
    var timedOut = false;
    unawaited(cancel?.whenCancelled.then((_) {
      cancelled = true;
      return proc.terminate(grace: const Duration(seconds: 1));
    }));

    final code = await proc.exitCode.timeout(timeout, onTimeout: () async {
      timedOut = true;
      await proc.terminate(grace: const Duration(seconds: 1));
      return -1;
    });
    await Future.wait([outDone, errDone]).timeout(
      const Duration(seconds: 3),
      onTimeout: () => const [],
    );

    if (cancelled) throw AppError.of(AppErrorKind.cancelled);
    if (timedOut) throw AppError.of(AppErrorKind.timeout, detail: 'metadata extraction');

    final stdoutText = out.toString();
    // On failure yt-dlp prints nothing or the literal `null`; only continue
    // when it still produced a JSON object (partially failing playlists).
    if (code != 0 && !stdoutText.trimLeft().startsWith('{')) {
      final error = ErrorClassifier.fromProcessOutput(err.toString(), exitCode: code);
      _log.warning('metadata failed: ${error.detail}');
      throw error;
    }
    if (code != 0) {
      // yt-dlp may still print usable JSON for partially failing playlists.
      _log.info('metadata exited with $code but produced output; continuing');
    }

    final info = await parseInIsolate(stdoutText, url);
    _log.info('metadata ok: ${info.kind.name}, ${info.totalCount} entries');
    return info;
  }

  /// Parses JSON off the UI isolate. Kept as a separate static function so
  /// the closure only captures sendable values.
  static Future<MediaInfo> parseInIsolate(String json, String url) => Isolate.run(
        () => MetadataParser.parseJson(json, sourceUrl: url),
        debugName: 'metadata-parse',
      );
}
