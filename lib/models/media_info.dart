import 'dart:math' as math;

import 'download_options.dart';

/// Availability of a playlist entry as reported by yt-dlp.
enum EntryAvailability {
  available,
  unavailable,
  private,
  needsAuth,
  live,
  nestedPlaylist;

  bool get isDownloadable => this == EntryAvailability.available;

  String get label => switch (this) {
        EntryAvailability.available => 'Available',
        EntryAvailability.unavailable => 'Unavailable',
        EntryAvailability.private => 'Private',
        EntryAvailability.needsAuth => 'Requires sign-in',
        EntryAvailability.live => 'Live stream',
        EntryAvailability.nestedPlaylist => 'Nested playlist',
      };

  String get explanation => switch (this) {
        EntryAvailability.available => '',
        EntryAvailability.unavailable => 'This video was removed or is blocked.',
        EntryAvailability.private => 'This video is private.',
        EntryAvailability.needsAuth =>
          'This video requires signing in or a membership.',
        EntryAvailability.live =>
          'Live streams aren\'t supported. Download it after the stream ends.',
        EntryAvailability.nestedPlaylist =>
          'This item is itself a playlist. Paste its link separately.',
      };
}

/// A single downloadable stream description.
class MediaFormat {
  const MediaFormat({
    required this.formatId,
    this.ext,
    this.width,
    this.height,
    this.fps,
    this.vcodec,
    this.acodec,
    this.filesize,
    this.bitrate,
    this.note,
  });

  final String formatId;
  final String? ext;
  final int? width;
  final int? height;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final int? filesize;
  final double? bitrate;
  final String? note;

  bool get hasVideo =>
      vcodec != 'none' && (vcodec != null || (height ?? 0) > 0);
  bool get hasAudio => acodec != null && acodec != 'none';

  /// Resolution measured on the short side (handles vertical video), matching
  /// yt-dlp's `res` sort field.
  int? get res {
    if (width != null && height != null) return math.min(width!, height!);
    return height;
  }
}

/// One video, either standalone or as part of a playlist.
class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.url,
    required this.extractor,
    this.thumbnailUrl,
    this.duration,
    this.playlistIndex,
    this.uploader,
    this.availability = EntryAvailability.available,
    this.formats = const [],
  });

  final String id;
  final String title;
  final String url;
  final String extractor;
  final String? thumbnailUrl;
  final Duration? duration;
  final int? playlistIndex;
  final String? uploader;
  final EntryAvailability availability;

  /// Empty for flat playlist entries (formats are resolved at download time).
  final List<MediaFormat> formats;

  /// Stable identifier used for deduplication across sessions.
  String get stableId => '${extractor.toLowerCase()}:$id';

  bool get hasFormatInfo => formats.isNotEmpty;

  /// Quality presets that this video can actually satisfy.
  Set<VideoQuality> get availableQualities {
    if (!hasFormatInfo) return VideoQuality.values.toSet();
    final out = <VideoQuality>{VideoQuality.best};
    for (final f in formats) {
      if (!f.hasVideo) continue;
      final r = f.res;
      if (r == null) continue;
      final q = VideoQuality.bucketFor(r);
      if (q != null) out.add(q);
    }
    return out;
  }

  /// The highest video resolution available, if known.
  int? get maxResolution {
    int? best;
    for (final f in formats) {
      if (!f.hasVideo || f.res == null) continue;
      if (best == null || f.res! > best) best = f.res;
    }
    return best;
  }

  bool get hasAudioStreams => formats.any((f) => f.hasAudio);
}

enum MediaKind { video, playlist }

/// Result of metadata extraction for a URL.
class MediaInfo {
  const MediaInfo({
    required this.kind,
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.extractor,
    required this.entries,
    this.uploader,
    this.thumbnailUrl,
    this.description,
    this.reportedCount,
  });

  final MediaKind kind;
  final String id;
  final String title;
  final String sourceUrl;
  final String extractor;
  final List<MediaEntry> entries;
  final String? uploader;
  final String? thumbnailUrl;
  final String? description;

  /// Count reported by the source (may exceed [entries] when items are hidden).
  final int? reportedCount;

  bool get isPlaylist => kind == MediaKind.playlist;

  int get totalCount => entries.length;

  int get downloadableCount =>
      entries.where((e) => e.availability.isDownloadable).length;

  int get unavailableCount => totalCount - downloadableCount;

  /// Sum of known durations; null when no entry reports one.
  Duration? get totalDuration {
    var any = false;
    var total = Duration.zero;
    for (final e in entries) {
      if (e.duration != null) {
        any = true;
        total += e.duration!;
      }
    }
    return any ? total : null;
  }

  /// Number of entries without a known duration.
  int get entriesWithoutDuration => entries.where((e) => e.duration == null).length;
}
