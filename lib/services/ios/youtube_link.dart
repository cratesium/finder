import '../../core/errors/app_error.dart';
import '../../models/download_options.dart';

/// What a link resolves to for the iOS engine.
sealed class YoutubeTarget {
  const YoutubeTarget();
}

class YoutubeVideoTarget extends YoutubeTarget {
  const YoutubeVideoTarget(this.videoId);
  final String videoId;
}

class YoutubePlaylistTarget extends YoutubeTarget {
  const YoutubePlaylistTarget(this.playlistId);
  final String playlistId;
}

/// Parses YouTube links without any network access.
///
/// iOS can't run yt-dlp, so the iOS engine supports YouTube only. Everything
/// else is rejected with a clear [AppErrorKind.unsupportedSource] error.
abstract final class YoutubeLink {
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
    'youtu.be',
  };

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _listPattern = RegExp(r'^[A-Za-z0-9_-]{10,}$');

  static bool isYoutube(Uri uri) => _hosts.contains(uri.host.toLowerCase());

  /// The 11-character video id in [uri], if any.
  static String? videoId(Uri uri) {
    final host = uri.host.toLowerCase();
    String? id;
    if (host == 'youtu.be') {
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else {
      final segs = uri.pathSegments;
      if (segs.isNotEmpty && segs.first == 'watch') {
        id = uri.queryParameters['v'];
      } else if (segs.length >= 2 && const {'shorts', 'embed', 'live', 'v', 'e'}.contains(segs.first)) {
        id = segs[1];
      }
    }
    return id != null && _idPattern.hasMatch(id) ? id : null;
  }

  /// The playlist id in [uri], if any. Auto-generated mixes (`RD…`) can't be
  /// listed and are ignored.
  static String? playlistId(Uri uri) {
    final list = uri.queryParameters['list'];
    if (list == null || !_listPattern.hasMatch(list) || list.startsWith('RD')) return null;
    return list;
  }

  /// Decides what to read from [url] given the user's [scope].
  static YoutubeTarget resolve(String url, FetchScope scope) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !isYoutube(uri)) {
      throw const AppError(
        AppErrorKind.unsupportedSource,
        'On iPhone and iPad, Finder can download from YouTube links only. '
        'Use Finder on a Mac, Windows or Linux computer, or Android, for other sites.',
      );
    }
    final video = videoId(uri);
    final list = playlistId(uri);
    final target = switch (scope) {
      FetchScope.single => video != null ? YoutubeVideoTarget(video) : null,
      FetchScope.playlist => list != null ? YoutubePlaylistTarget(list) : null,
      // Same rule as yt-dlp: a link with a playlist is read as the playlist.
      FetchScope.auto =>
        list != null ? YoutubePlaylistTarget(list) : (video != null ? YoutubeVideoTarget(video) : null),
    };
    if (target != null) return target;
    throw AppError(AppErrorKind.invalidUrl, switch (scope) {
      FetchScope.single => 'This link doesn\'t point to a single YouTube video.',
      FetchScope.playlist => 'This link doesn\'t contain a YouTube playlist.',
      FetchScope.auto => 'This YouTube link doesn\'t point to a video or playlist.',
    });
  }
}
