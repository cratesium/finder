import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'resumable_writer.dart';
import 'stream_selection.dart';

class YoutubeVideoDetails {
  const YoutubeVideoDetails({
    required this.id,
    required this.title,
    this.author,
    this.duration,
    this.thumbnailUrl,
    this.isLive = false,
  });
  final String id;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;
  final bool isLive;
}

class YoutubePlaylistDetails {
  const YoutubePlaylistDetails({
    required this.id,
    required this.title,
    this.author,
    this.videoCount,
    this.thumbnailUrl,
  });
  final String id;
  final String title;
  final String? author;
  final int? videoCount;
  final String? thumbnailUrl;
}

/// Everything the iOS engine needs from YouTube. Abstracted so the engine is
/// unit-testable without network access.
abstract interface class YoutubeGateway {
  Future<YoutubeVideoDetails> video(String id);
  Future<List<StreamCandidate>> streams(String videoId);
  Future<YoutubePlaylistDetails> playlist(String id);
  Stream<YoutubeVideoDetails> playlistVideos(String id);

  /// Bytes of [stream] from offset `start` (chunked HTTP range requests).
  ByteSource open(StreamCandidate stream);

  /// Whether an interrupted download of [stream] can continue from an offset.
  bool isResumable(StreamCandidate stream);
}

/// [YoutubeGateway] backed by `youtube_explode_dart` (pure Dart).
class YoutubeExplodeGateway implements YoutubeGateway {
  YoutubeExplodeGateway() : _http = yt.YoutubeHttpClient() {
    _client = yt.YoutubeExplode(httpClient: _http);
  }

  final yt.YoutubeHttpClient _http;
  late final yt.YoutubeExplode _client;

  static YoutubeVideoDetails _details(yt.Video v) => YoutubeVideoDetails(
    id: v.id.value,
    title: v.title,
    author: v.author.isEmpty ? null : v.author,
    duration: v.duration,
    thumbnailUrl: v.thumbnails.highResUrl,
    isLive: v.isLive,
  );

  @override
  Future<YoutubeVideoDetails> video(String id) async => _details(await _client.videos.get(id));

  @override
  Future<List<StreamCandidate>> streams(String videoId) async {
    final manifest = await _client.videos.streamsClient.getManifest(videoId);
    return [
      for (final s in manifest.streams)
        if (s is yt.MuxedStreamInfo)
          StreamCandidate(
            kind: StreamKind.muxed,
            tag: s.tag,
            container: s.container.name,
            videoCodec: s.videoCodec,
            audioCodec: s.audioCodec,
            width: s.videoResolution.width,
            height: s.videoResolution.height,
            fps: s.framerate.framesPerSecond,
            bitrate: s.bitrate.bitsPerSecond,
            size: s.size.totalBytes,
            ref: s,
          )
        else if (s is yt.VideoOnlyStreamInfo)
          StreamCandidate(
            kind: StreamKind.videoOnly,
            tag: s.tag,
            container: s.container.name,
            videoCodec: s.videoCodec,
            width: s.videoResolution.width,
            height: s.videoResolution.height,
            fps: s.framerate.framesPerSecond,
            bitrate: s.bitrate.bitsPerSecond,
            size: s.size.totalBytes,
            ref: s,
          )
        else if (s is yt.AudioOnlyStreamInfo)
          StreamCandidate(
            kind: StreamKind.audioOnly,
            tag: s.tag,
            container: s.container.name,
            audioCodec: s.audioCodec,
            bitrate: s.bitrate.bitsPerSecond,
            size: s.size.totalBytes,
            ref: s,
          ),
    ];
  }

  @override
  Future<YoutubePlaylistDetails> playlist(String id) async {
    final p = await _client.playlists.get(id);
    return YoutubePlaylistDetails(
      id: p.id.value,
      title: p.title,
      author: p.author.isEmpty ? null : p.author,
      videoCount: p.videoCount,
      thumbnailUrl: p.thumbnails.highResUrl,
    );
  }

  @override
  Stream<YoutubeVideoDetails> playlistVideos(String id) => _client.playlists.getVideos(id).map(_details);

  @override
  ByteSource open(StreamCandidate stream) {
    final info = stream.ref! as yt.StreamInfo;
    // The library requests 10 MB ranges for throttled streams and refreshes
    // expired stream URLs, which keeps long downloads from stalling.
    return (start) => _http.getStream(info, start: start, streamClient: _client.videos.streamsClient);
  }

  @override
  bool isResumable(StreamCandidate stream) => (stream.ref! as yt.StreamInfo).fragments.isEmpty;

  void close() => _client.close();
}
