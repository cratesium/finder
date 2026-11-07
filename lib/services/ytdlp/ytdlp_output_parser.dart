import 'ytdlp_args.dart';

/// Events produced from yt-dlp output lines.
sealed class YtDlpEvent {
  const YtDlpEvent();
}

class ProgressEvent extends YtDlpEvent {
  const ProgressEvent({
    required this.status,
    this.downloadedBytes,
    this.totalBytes,
    this.totalBytesEstimate,
    this.speed,
    this.eta,
    this.fragmentIndex,
    this.fragmentCount,
    this.formatId,
  });

  /// `downloading`, `finished` or `error`.
  final String status;
  final int? downloadedBytes;
  final int? totalBytes;
  final int? totalBytesEstimate;
  final double? speed;
  final int? eta;
  final int? fragmentIndex;
  final int? fragmentCount;
  final String? formatId;
}

class PostProcessEvent extends YtDlpEvent {
  const PostProcessEvent({required this.status, this.postprocessor});
  final String status;
  final String? postprocessor;

  String get label => switch (postprocessor) {
        'Merger' => 'Merging audio and video',
        'FFmpegMerger' => 'Merging audio and video',
        'ExtractAudio' || 'FFmpegExtractAudio' => 'Extracting audio',
        'VideoRemuxer' || 'FFmpegVideoRemuxer' => 'Remuxing container',
        'MoveFiles' => 'Finalizing',
        null => 'Processing',
        final other => 'Processing ($other)',
      };
}

class DestinationEvent extends YtDlpEvent {
  const DestinationEvent(this.path);
  final String path;
}

class FileEvent extends YtDlpEvent {
  const FileEvent(this.path);
  final String path;
}

class MetaEvent extends YtDlpEvent {
  const MetaEvent({this.height, this.width, this.ext});
  final int? height;
  final int? width;
  final String? ext;

  int? get res {
    final h = height, w = width;
    if (h != null && w != null) return h < w ? h : w;
    return h;
  }
}

/// Any other line, kept for diagnostics.
class LogLineEvent extends YtDlpEvent {
  const LogLineEvent(this.line, {this.isError = false, this.isWarning = false});
  final String line;
  final bool isError;
  final bool isWarning;
}

/// Parses individual lines emitted by yt-dlp using [YtDlpArgs] templates.
abstract final class YtDlpOutputParser {
  static YtDlpEvent parse(String rawLine) {
    final line = rawLine.trimRight();
    final idx = line.indexOf(YtDlpArgs.marker);
    if (idx < 0) {
      final t = line.trimLeft();
      return LogLineEvent(
        line,
        isError: t.startsWith('ERROR:'),
        isWarning: t.startsWith('WARNING:'),
      );
    }
    final payload = line.substring(idx + YtDlpArgs.marker.length);
    final sep = payload.indexOf('|');
    if (sep < 0) return LogLineEvent(line);
    final type = payload.substring(0, sep);
    final rest = payload.substring(sep + 1);
    switch (type) {
      case 'dl':
        final f = rest.split('|');
        String? at(int i) => i < f.length ? f[i] : null;
        return ProgressEvent(
          status: at(0) ?? 'downloading',
          downloadedBytes: _int(at(1)),
          totalBytes: _int(at(2)),
          totalBytesEstimate: _int(at(3)),
          speed: _double(at(4)),
          eta: _int(at(5)),
          fragmentIndex: _int(at(6)),
          fragmentCount: _int(at(7)),
          formatId: _str(f.length > 8 ? f.sublist(8).join('|') : null),
        );
      case 'pp':
        final f = rest.split('|');
        return PostProcessEvent(
          status: f.first,
          postprocessor: _str(f.length > 1 ? f[1] : null),
        );
      case 'dest':
        // Path is the remainder; it may itself contain '|'.
        return DestinationEvent(rest);
      case 'file':
        return FileEvent(rest);
      case 'meta':
        final f = rest.split('|');
        return MetaEvent(
          height: _int(f.isNotEmpty ? f[0] : null),
          width: _int(f.length > 1 ? f[1] : null),
          ext: _str(f.length > 2 ? f[2] : null),
        );
      default:
        return LogLineEvent(line);
    }
  }

  static String? _str(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty || t == 'NA' || t == 'None' || t == 'null') return null;
    return t;
  }

  static double? _double(String? s) {
    final t = _str(s);
    return t == null ? null : double.tryParse(t);
  }

  static int? _int(String? s) {
    final d = _double(s);
    if (d == null || d.isNaN || d.isInfinite) return null;
    return d.round();
  }
}
