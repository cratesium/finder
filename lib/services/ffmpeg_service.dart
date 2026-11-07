import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'process_service.dart';

final _log = Logger('ffmpeg');

/// Information about a finished media file, read with ffprobe.
class MediaProbe {
  const MediaProbe({this.width, this.height, this.hasVideo = false, this.hasAudio = false});
  final int? width;
  final int? height;
  final bool hasVideo;
  final bool hasAudio;

  int? get res {
    if (width != null && height != null) return width! < height! ? width : height;
    return height;
  }
}

/// FFmpeg integration. Stream merging itself is driven by yt-dlp through
/// `--ffmpeg-location`; this service handles version detection and probing.
class FfmpegService {
  FfmpegService(this._processes);

  final ProcessService _processes;

  static final _versionPattern = RegExp(r'(?:ffmpeg|ffprobe) version (\S+)');

  static String? parseVersion(String output) {
    final m = _versionPattern.firstMatch(output);
    if (m == null) return null;
    var v = m.group(1)!;
    // Trim build suffixes like "-tessus" or "-essentials_build-www.gyan.dev".
    final sep = v.indexOf(RegExp(r'-(?:tessus|essentials|full|static)'));
    if (sep > 0) v = v.substring(0, sep);
    return v;
  }

  /// ffprobe lives next to ffmpeg in every distribution we support.
  static String ffprobePathFor(String ffmpegPath) {
    final dir = p.dirname(ffmpegPath);
    final ext = p.extension(ffmpegPath);
    return p.join(dir, 'ffprobe$ext');
  }

  Future<String?> version(String ffmpegPath) async {
    final r = await _processes.run(ffmpegPath, ['-hide_banner', '-version']);
    return r.ok ? parseVersion(r.stdout) : null;
  }

  /// Reads stream information of [file]. Returns null if ffprobe is missing or
  /// fails; callers treat probing as best-effort.
  Future<MediaProbe?> probe(String ffmpegPath, String file) async {
    final ffprobe = ffprobePathFor(ffmpegPath);
    if (!await File(ffprobe).exists()) return null;
    final r = await _processes.run(ffprobe, [
      '-v', 'error',
      '-show_entries', 'stream=codec_type,width,height',
      '-of', 'csv=p=0',
      // Absolute path, so it can never be parsed as an option.
      p.absolute(file),
    ]);
    if (!r.ok) {
      _log.fine('ffprobe failed: ${r.stderr}');
      return null;
    }
    return parseProbe(r.stdout);
  }

  /// Parses `codec_type,width,height` CSV rows.
  static MediaProbe parseProbe(String csv) {
    int? w, h;
    var video = false, audio = false;
    for (final line in csv.split(RegExp(r'\r?\n'))) {
      final cols = line.trim().split(',');
      if (cols.isEmpty || cols.first.isEmpty) continue;
      if (cols.first == 'video') {
        video = true;
        if (cols.length >= 3 && w == null) {
          w = int.tryParse(cols[1]);
          h = int.tryParse(cols[2]);
        }
      } else if (cols.first == 'audio') {
        audio = true;
      }
    }
    return MediaProbe(width: w, height: h, hasVideo: video, hasAudio: audio);
  }
}
