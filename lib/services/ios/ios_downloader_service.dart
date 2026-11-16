import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_error.dart';
import '../../models/download_options.dart';
import '../downloader_service.dart';
import '../ytdlp/ytdlp_output_parser.dart';
import 'ios_bridge.dart';
import 'ios_errors.dart';
import 'resumable_writer.dart';
import 'stream_selection.dart';
import 'youtube_gateway.dart';
import 'youtube_link.dart';

final _log = Logger('ios.downloader');

/// Downloads on iOS without yt-dlp/FFmpeg.
///
/// Emits the same [YtDlpEvent]s the desktop engine produces, so the shared
/// download manager, progress UI, pause/resume and cleanup work unchanged:
/// * one `ProgressEvent` stream per media stream (`formatId` = YouTube itag),
/// * a `PostProcessEvent('Merger')` while AVFoundation joins video + audio,
/// * `MetaEvent` / `FileEvent` for the finished file.
///
/// Partial files follow yt-dlp's naming (`<name>.f<itag>.mp4.part`), so pause
/// keeps them, resume continues with an HTTP range request, and cancel removes
/// them.
class IosDownloaderService implements DownloaderService {
  IosDownloaderService({required this.gateway, required this.muxer, required this.background});

  final YoutubeGateway gateway;
  final Muxer muxer;
  final BackgroundTasks background;

  @override
  Future<DownloadJob> start(DownloadJobSpec spec) async => IosDownloadJob(spec, this);
}

class IosDownloadJob implements DownloadJob {
  IosDownloadJob(this.spec, this._svc) {
    _outcome = _run();
  }

  final DownloadJobSpec spec;
  final IosDownloaderService _svc;
  final _events = StreamController<YtDlpEvent>.broadcast();
  final _destinations = <String>[];
  final _writer = ResumableWriter();
  late final Future<DownloadOutcome> _outcome;
  bool _stopRequested = false;

  @override
  Stream<YtDlpEvent> get events => _events.stream;
  @override
  Future<DownloadOutcome> get outcome => _outcome;
  @override
  List<String> get announcedDestinations => List.unmodifiable(_destinations);

  void _emit(YtDlpEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    _writer.stop();
    await _outcome.catchError((_) => const DownloadStopped());
  }

  Future<DownloadOutcome> _run() async {
    // Let listeners attach before the first event.
    await Future<void>.delayed(Duration.zero);
    final bgTask = await _svc.background.begin('Finder download');
    try {
      final outcome = await _download();
      return _stopRequested ? const DownloadStopped() : outcome;
    } catch (e, st) {
      if (_stopRequested) return const DownloadStopped();
      final err = IosErrors.map(e);
      _log.warning('download failed: ${err.kind.name} ${err.detail ?? ''}', e, st);
      return DownloadFailed(err);
    } finally {
      await _svc.background.end(bgTask);
      await _events.close();
    }
  }

  Future<DownloadOutcome> _download() async {
    final uri = Uri.tryParse(spec.url);
    final id = uri == null ? null : YoutubeLink.videoId(uri);
    if (id == null) {
      // Throws the same "YouTube only on iOS" / "not a video" errors as
      // metadata extraction.
      YoutubeLink.resolve(spec.url, FetchScope.single);
      throw const AppError(AppErrorKind.invalidUrl, 'This link doesn\'t point to a single video.');
    }
    final details = await _svc.gateway.video(id);
    final streams = await _svc.gateway.streams(id);
    final plan = StreamSelector.select(streams, spec.options);
    if (plan == null) {
      throw const AppError(
        AppErrorKind.formatUnavailable,
        'YouTube doesn\'t offer this video in a format iPhone and iPad can save.',
      );
    }
    if (_stopRequested) return const DownloadStopped();

    final name = OutputName.render(spec.outputTemplate, title: details.title, id: id, ext: plan.extension);
    final finalPath = p.join(spec.directory, name);
    _destinations.add(finalPath);
    _emit(DestinationEvent(finalPath));
    await Directory(spec.directory).create(recursive: true);

    if (await File(finalPath).exists()) {
      _log.info('already downloaded');
    } else {
      switch (plan) {
        case SinglePlan(:final stream):
          final part = File('$finalPath.part');
          if (!await _fetch(stream, part)) return const DownloadStopped();
          await part.rename(finalPath);
        case SeparatePlan(:final video, :final audio):
          final stem = p.join(spec.directory, p.basenameWithoutExtension(name));
          final videoFile = '$stem.f${video.tag}.mp4';
          final audioFile = '$stem.f${audio.tag}.m4a';
          for (final (s, path) in [(video, videoFile), (audio, audioFile)]) {
            if (await File(path).exists()) continue; // finished before a pause
            final part = File('$path.part');
            if (!await _fetch(s, part)) return const DownloadStopped();
            await part.rename(path);
          }
          if (_stopRequested) return const DownloadStopped();
          _emit(const PostProcessEvent(status: 'started', postprocessor: 'Merger'));
          final temp = '$stem.temp.mp4';
          final tempFile = File(temp);
          if (await tempFile.exists()) await tempFile.delete();
          await _svc.muxer.mux(videoPath: videoFile, audioPath: audioFile, outputPath: temp);
          _emit(const PostProcessEvent(status: 'finished', postprocessor: 'Merger'));
          await tempFile.rename(finalPath);
          for (final f in [videoFile, audioFile]) {
            try {
              await File(f).delete();
            } catch (_) {}
          }
      }
    }

    final res = plan.resolution;
    _emit(MetaEvent(height: res, ext: plan.extension));
    _emit(FileEvent(finalPath));
    return DownloadSucceeded(filePath: finalPath, resolution: res, extension: plan.extension);
  }

  /// Downloads [stream] into [part]. Returns false when stopped.
  Future<bool> _fetch(StreamCandidate stream, File part) async {
    if (_stopRequested) return false;
    final result = await _writer.write(
      partial: part,
      source: _svc.gateway.open(stream),
      totalBytes: stream.size,
      resumable: _svc.gateway.isResumable(stream),
      onProgress: (w) => _emit(
        ProgressEvent(
          status: 'downloading',
          downloadedBytes: w.downloaded,
          totalBytes: w.total,
          speed: w.speed,
          eta: w.eta,
          formatId: '${stream.tag}',
        ),
      ),
    );
    if (result == WriteResult.stopped || _stopRequested) return false;
    final size = await part.length();
    _emit(
      ProgressEvent(
        status: 'finished',
        downloadedBytes: size,
        totalBytes: stream.size ?? size,
        formatId: '${stream.tag}',
      ),
    );
    return true;
  }
}
