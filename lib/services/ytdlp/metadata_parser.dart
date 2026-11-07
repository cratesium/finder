import 'dart:convert';

import '../../core/errors/app_error.dart';
import '../../models/media_info.dart';

/// Converts yt-dlp `--dump-single-json --flat-playlist` output to [MediaInfo].
///
/// Pure function; runs inside an isolate for large playlists.
abstract final class MetadataParser {
  static const _unavailableTitles = {
    '[private video]',
    '[deleted video]',
    '[unavailable video]',
  };

  static MediaInfo parseJson(String jsonText, {required String sourceUrl}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw AppError(AppErrorKind.unknown,
          'yt-dlp returned data CourseGrab couldn\'t understand.',
          detail: 'invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const AppError(AppErrorKind.unknown,
          'yt-dlp returned data CourseGrab couldn\'t understand.',
          detail: 'top-level JSON is not an object');
    }
    return parse(decoded, sourceUrl: sourceUrl);
  }

  static MediaInfo parse(Map<String, Object?> json, {required String sourceUrl}) {
    final type = json['_type'] as String?;
    final extractor = _extractor(json);
    if (type == 'playlist' || json['entries'] is List) {
      final rawEntries = (json['entries'] as List?) ?? const [];
      final entries = <MediaEntry>[];
      for (var i = 0; i < rawEntries.length; i++) {
        final raw = rawEntries[i];
        if (raw is! Map<String, Object?>) {
          entries.add(MediaEntry(
            id: 'missing-${i + 1}',
            title: 'Unavailable item',
            url: '',
            extractor: extractor,
            playlistIndex: i + 1,
            availability: EntryAvailability.unavailable,
          ));
          continue;
        }
        entries.add(_entry(raw, fallbackIndex: i + 1, fallbackExtractor: extractor));
      }
      return MediaInfo(
        kind: MediaKind.playlist,
        id: _s(json['id']) ?? sourceUrl,
        title: _s(json['title']) ?? 'Untitled playlist',
        sourceUrl: _s(json['webpage_url']) ?? sourceUrl,
        extractor: extractor,
        entries: entries,
        uploader: _s(json['channel']) ?? _s(json['uploader']),
        thumbnailUrl: _thumbnail(json) ??
            entries.map((e) => e.thumbnailUrl).whereType<String>().firstOrNull,
        description: _s(json['description']),
        reportedCount: _i(json['playlist_count']),
      );
    }

    final formats = _formats(json);
    final hasDrmOnly = formats.isEmpty &&
        (json['formats'] as List?)?.isNotEmpty == true &&
        (json['formats'] as List).every((f) => f is Map && f['has_drm'] == true);
    if (hasDrmOnly) throw AppError.of(AppErrorKind.drmProtected);

    final entry = _entry(json, fallbackIndex: null, fallbackExtractor: extractor, formats: formats);
    return MediaInfo(
      kind: MediaKind.video,
      id: entry.id,
      title: entry.title,
      sourceUrl: entry.url.isEmpty ? sourceUrl : entry.url,
      extractor: extractor,
      entries: [entry],
      uploader: entry.uploader,
      thumbnailUrl: entry.thumbnailUrl,
      description: _s(json['description']),
    );
  }

  static MediaEntry _entry(
    Map<String, Object?> e, {
    required int? fallbackIndex,
    required String fallbackExtractor,
    List<MediaFormat>? formats,
  }) {
    final id = _s(e['id']) ?? 'item-${fallbackIndex ?? 0}';
    final title = _s(e['title']) ?? _s(e['fulltitle']) ?? id;
    final url = _s(e['webpage_url']) ?? _s(e['original_url']) ?? _s(e['url']) ?? '';
    final durationSec = _d(e['duration']);
    return MediaEntry(
      id: id,
      title: title,
      url: url,
      extractor: _extractor(e, fallback: fallbackExtractor),
      thumbnailUrl: _thumbnail(e),
      duration: durationSec == null || durationSec <= 0
          ? null
          : Duration(milliseconds: (durationSec * 1000).round()),
      playlistIndex: _i(e['playlist_index']) ?? fallbackIndex,
      uploader: _s(e['channel']) ?? _s(e['uploader']),
      availability: _availability(e, title, url),
      formats: formats ?? const [],
    );
  }

  static EntryAvailability _availability(Map<String, Object?> e, String title, String url) {
    if (_unavailableTitles.contains(title.toLowerCase())) {
      return title.toLowerCase().contains('private')
          ? EntryAvailability.private
          : EntryAvailability.unavailable;
    }
    final type = _s(e['_type']);
    final ieKey = (_s(e['ie_key']) ?? '').toLowerCase();
    if (type == 'playlist' || ieKey.endsWith('tab') || ieKey.endsWith('playlist')) {
      return EntryAvailability.nestedPlaylist;
    }
    if (e['is_live'] == true || _s(e['live_status']) == 'is_live') {
      return EntryAvailability.live;
    }
    switch (_s(e['availability'])) {
      case 'private':
        return EntryAvailability.private;
      case 'premium_only':
      case 'subscriber_only':
      case 'needs_auth':
        return EntryAvailability.needsAuth;
    }
    if (url.isEmpty) return EntryAvailability.unavailable;
    return EntryAvailability.available;
  }

  static List<MediaFormat> _formats(Map<String, Object?> json) {
    final raw = json['formats'];
    if (raw is! List) return const [];
    final out = <MediaFormat>[];
    for (final f in raw) {
      if (f is! Map<String, Object?>) continue;
      if (f['has_drm'] == true) continue;
      final id = _s(f['format_id']);
      if (id == null) continue;
      // Storyboards / images aren't media.
      if (_s(f['ext']) == 'mhtml') continue;
      out.add(MediaFormat(
        formatId: id,
        ext: _s(f['ext']),
        width: _i(f['width']),
        height: _i(f['height']),
        fps: _d(f['fps']),
        vcodec: _s(f['vcodec']),
        acodec: _s(f['acodec']),
        filesize: _i(f['filesize']) ?? _i(f['filesize_approx']),
        bitrate: _d(f['tbr']),
        note: _s(f['format_note']),
      ));
    }
    return out;
  }

  static String _extractor(Map<String, Object?> json, {String fallback = 'generic'}) =>
      _s(json['extractor_key']) ?? _s(json['ie_key']) ?? _s(json['extractor']) ?? fallback;

  static String? _thumbnail(Map<String, Object?> json) {
    final thumbs = json['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty) {
      // Prefer a thumbnail close to 480px wide to keep memory usage low.
      String? best;
      var bestScore = 1 << 30;
      for (final t in thumbs) {
        if (t is! Map) continue;
        final url = _s(t['url']);
        if (url == null || !url.startsWith('http')) continue;
        final w = _i(t['width']);
        final score = w == null ? 100000 : (w - 480).abs();
        if (score < bestScore) {
          bestScore = score;
          best = url;
        }
      }
      if (best != null) return best;
    }
    final single = _s(json['thumbnail']);
    return single != null && single.startsWith('http') ? single : null;
  }

  static String? _s(Object? v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is num) return v.toString();
    return null;
  }

  static double? _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static int? _i(Object? v) => _d(v)?.round();
}
