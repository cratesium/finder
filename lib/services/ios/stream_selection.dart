import 'dart:convert';
import 'dart:math' as math;

import '../../core/utils/path_utils.dart';
import '../../models/download_options.dart';
import '../../models/media_info.dart';

enum StreamKind { videoOnly, audioOnly, muxed }

/// Library-independent description of one stream offered by YouTube.
///
/// [ref] carries the original library object so the downloader can fetch it.
class StreamCandidate {
  const StreamCandidate({
    required this.kind,
    required this.tag,
    required this.container,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.fps,
    this.bitrate,
    this.size,
    this.ref,
  });

  final StreamKind kind;
  final int tag;

  /// `mp4`, `webm`, …
  final String container;
  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;
  final num? fps;

  /// Bits per second.
  final int? bitrate;
  final int? size;
  final Object? ref;

  /// Short-side resolution, matching yt-dlp's `res` (handles vertical video).
  int? get res {
    final w = width, h = height;
    if (w != null && h != null) return math.min(w, h);
    return h;
  }

  bool get _mp4 => container.toLowerCase() == 'mp4';
  bool get _avc => (videoCodec ?? '').toLowerCase().startsWith('avc1');

  /// Streams AVFoundation can play and mux on every supported iOS device:
  /// H.264 video in MP4, AAC audio in MP4 (m4a). VP9/AV1/WebM are skipped.
  bool get isIosCompatible => switch (kind) {
    StreamKind.videoOnly => _mp4 && _avc,
    StreamKind.audioOnly => _mp4,
    StreamKind.muxed => _mp4,
  };

  MediaFormat toMediaFormat() => MediaFormat(
    formatId: '$tag',
    ext: kind == StreamKind.audioOnly ? 'm4a' : container,
    width: width,
    height: height,
    fps: fps?.toDouble(),
    vcodec: kind == StreamKind.audioOnly ? 'none' : videoCodec,
    acodec: kind == StreamKind.videoOnly ? 'none' : (audioCodec ?? 'mp4a'),
    filesize: size,
    bitrate: bitrate == null ? null : bitrate! / 1000,
  );
}

/// What to download for one task.
sealed class StreamPlan {
  const StreamPlan();
  List<StreamCandidate> get streams;

  /// Extension of the finished file.
  String get extension;

  /// Short-side resolution of the finished file (null for audio).
  int? get resolution;
}

/// Separate video and audio streams, muxed on the device afterwards.
class SeparatePlan extends StreamPlan {
  const SeparatePlan(this.video, this.audio);
  final StreamCandidate video;
  final StreamCandidate audio;
  @override
  List<StreamCandidate> get streams => [video, audio];
  @override
  String get extension => 'mp4';
  @override
  int? get resolution => video.res;
}

/// A single stream saved as-is (muxed video, or audio only).
class SinglePlan extends StreamPlan {
  const SinglePlan(this.stream);
  final StreamCandidate stream;
  @override
  List<StreamCandidate> get streams => [stream];
  @override
  String get extension => stream.kind == StreamKind.audioOnly ? 'm4a' : stream.container;
  @override
  int? get resolution => stream.kind == StreamKind.audioOnly ? null : stream.res;
}

abstract final class StreamSelector {
  /// Picks the best plan for [options] from [all], or null when YouTube offers
  /// nothing iOS can save. Mirrors yt-dlp's `-S res:N`: best at or below the
  /// requested resolution, otherwise the smallest above it.
  static StreamPlan? select(List<StreamCandidate> all, DownloadOptions options) {
    final usable = all.where((s) => s.isIosCompatible && (s.size ?? 1) > 0).toList();
    final audio = usable.where((s) => s.kind == StreamKind.audioOnly).toList()
      ..sort((a, b) => (b.bitrate ?? 0).compareTo(a.bitrate ?? 0));
    final muxed = usable.where((s) => s.kind == StreamKind.muxed && s.res != null).toList();

    if (options.isAudioOnly) {
      if (audio.isNotEmpty) return SinglePlan(audio.first);
      return null;
    }

    final target = options.quality.height;
    final videoOnly = usable.where((s) => s.kind == StreamKind.videoOnly && s.res != null).toList();
    final bestMuxed = pickVideo(muxed, target);
    // Choose the resolution across both kinds, so an exact muxed match beats
    // a video-only stream further from the target.
    final best = pickVideo([if (audio.isNotEmpty) ...videoOnly, ...muxed], target);
    if (best == null) return null;
    if (best.kind == StreamKind.muxed) return SinglePlan(best);
    // A muxed stream at the same resolution needs no on-device merge.
    if (bestMuxed != null && (bestMuxed.res ?? 0) >= (best.res ?? 0)) return SinglePlan(bestMuxed);
    if (audio.isNotEmpty) return SeparatePlan(best, audio.first);
    return bestMuxed == null ? null : SinglePlan(bestMuxed);
  }

  static StreamCandidate? pickVideo(List<StreamCandidate> videos, int? target) {
    if (videos.isEmpty) return null;
    int cmp(StreamCandidate a, StreamCandidate b) {
      final r = (a.res ?? 0).compareTo(b.res ?? 0);
      if (r != 0) return r;
      final f = (a.fps ?? 0).compareTo(b.fps ?? 0);
      if (f != 0) return f;
      return (a.bitrate ?? 0).compareTo(b.bitrate ?? 0);
    }

    final sorted = [...videos]..sort(cmp); // ascending
    if (target == null) return sorted.last;
    final atOrBelow = sorted.where((s) => s.res! <= target).toList();
    if (atOrBelow.isNotEmpty) return atOrBelow.last;
    // Smallest above the target; among equal resolutions take the best one.
    final minRes = sorted.first.res;
    return sorted.lastWhere((s) => s.res == minRes);
  }
}

/// Renders the yt-dlp style output template used by the download manager
/// (`[NNN - ]%(title).180B [%(id)s].%(ext)s`) for the iOS engine.
abstract final class OutputName {
  static String render(String template, {required String title, required String id, required String ext}) {
    final safeTitle = _truncateBytes(PathUtils.sanitizeSegment(title, maxLength: 400), 180);
    final buf = StringBuffer();
    var i = 0;
    while (i < template.length) {
      if (template.startsWith('%%', i)) {
        buf.write('%');
        i += 2;
      } else if (template.startsWith('%(title).180B', i)) {
        buf.write(safeTitle);
        i += '%(title).180B'.length;
      } else if (template.startsWith('%(title)s', i)) {
        buf.write(safeTitle);
        i += '%(title)s'.length;
      } else if (template.startsWith('%(id)s', i)) {
        buf.write(PathUtils.sanitizeSegment(id));
        i += '%(id)s'.length;
      } else if (template.startsWith('%(ext)s', i)) {
        buf.write(ext);
        i += '%(ext)s'.length;
      } else {
        buf.write(template[i]);
        i++;
      }
    }
    return buf.toString();
  }

  static String _truncateBytes(String s, int maxBytes) {
    if (utf8.encode(s).length <= maxBytes) return s;
    final out = StringBuffer();
    var used = 0;
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final n = utf8.encode(ch).length;
      if (used + n > maxBytes) break;
      out.write(ch);
      used += n;
    }
    return out.toString().trim();
  }
}
