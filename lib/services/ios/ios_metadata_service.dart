import 'package:logging/logging.dart';

import '../../core/errors/app_error.dart';
import '../../models/download_options.dart';
import '../../models/media_info.dart';
import '../cancellation.dart';
import '../metadata_service.dart';
import '../trust_store_service.dart';
import 'ios_errors.dart';
import 'youtube_gateway.dart';
import 'youtube_link.dart';

final _log = Logger('ios.metadata');

/// Same `extractor_key` yt-dlp reports, so deduplication keys
/// (`youtube:<id>`) match across desktop, Android and iOS.
const iosExtractor = 'Youtube';

/// Metadata extraction on iOS (YouTube only; no yt-dlp process).
class IosMetadataService implements MetadataService {
  IosMetadataService(this._gateway, {this.timeout = const Duration(minutes: 3)});

  final YoutubeGateway _gateway;
  final Duration timeout;

  @override
  Future<MediaInfo> fetch(
    String url, {
    required String ytDlpPath,
    CancellationToken? cancel,
    YtDlpNetworkConfig network = YtDlpNetworkConfig.none,
    FetchScope scope = FetchScope.auto,
  }) async {
    final target = YoutubeLink.resolve(url, scope);
    _log.info('extracting metadata (${scope.name}, ${target.runtimeType})');
    final work = switch (target) {
      YoutubeVideoTarget(:final videoId) => _video(videoId, url),
      YoutubePlaylistTarget(:final playlistId) => _playlist(playlistId, url, cancel),
    };
    final guarded = work.timeout(timeout, onTimeout: () => throw AppError.of(AppErrorKind.timeout));
    try {
      if (cancel == null) return await guarded;
      return await Future.any([
        guarded,
        cancel.whenCancelled.then<MediaInfo>((_) => throw AppError.of(AppErrorKind.cancelled)),
      ]);
    } catch (e) {
      throw IosErrors.map(e);
    }
  }

  Future<MediaInfo> _video(String id, String url) async {
    final details = await _gateway.video(id);
    if (details.isLive) {
      throw const AppError(
        AppErrorKind.unavailable,
        'Live streams aren\'t supported. Download it after the stream ends.',
      );
    }
    final streams = await _gateway.streams(id);
    final formats = [
      for (final s in streams)
        if (s.isIosCompatible) s.toMediaFormat(),
    ];
    final entry = MediaEntry(
      id: details.id,
      title: details.title,
      url: 'https://www.youtube.com/watch?v=${details.id}',
      extractor: iosExtractor,
      thumbnailUrl: details.thumbnailUrl,
      duration: details.duration,
      uploader: details.author,
      formats: formats,
    );
    return MediaInfo(
      kind: MediaKind.video,
      id: details.id,
      title: details.title,
      sourceUrl: url,
      extractor: iosExtractor,
      entries: [entry],
      uploader: details.author,
      thumbnailUrl: details.thumbnailUrl,
    );
  }

  Future<MediaInfo> _playlist(String id, String url, CancellationToken? cancel) async {
    final pl = await _gateway.playlist(id);
    final entries = <MediaEntry>[];
    await for (final v in _gateway.playlistVideos(id)) {
      if (cancel?.isCancelled ?? false) throw AppError.of(AppErrorKind.cancelled);
      entries.add(
        MediaEntry(
          id: v.id,
          title: v.title,
          url: 'https://www.youtube.com/watch?v=${v.id}',
          extractor: iosExtractor,
          thumbnailUrl: v.thumbnailUrl,
          duration: v.duration,
          playlistIndex: entries.length + 1,
          uploader: v.author,
          availability: v.isLive ? EntryAvailability.live : EntryAvailability.available,
        ),
      );
    }
    return MediaInfo(
      kind: MediaKind.playlist,
      id: pl.id,
      title: pl.title,
      sourceUrl: url,
      extractor: iosExtractor,
      entries: entries,
      uploader: pl.author,
      thumbnailUrl: pl.thumbnailUrl ?? (entries.isEmpty ? null : entries.first.thumbnailUrl),
      reportedCount: pl.videoCount,
    );
  }
}
