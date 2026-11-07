import '../../core/utils/path_utils.dart';
import '../../models/download_options.dart';

/// Builds yt-dlp argument lists. Pure and side-effect free for testability.
///
/// Arguments are always returned as a list for `Process.start`; nothing here is
/// ever concatenated into a shell string.
abstract final class YtDlpArgs {
  /// Marker prefix for machine-readable lines emitted via templates.
  static const marker = '[cg]';

  /// Options common to every invocation. `--ignore-config` ensures a user's
  /// global yt-dlp config can't change behaviour or inject options.
  static const List<String> base = [
    '--ignore-config',
    '--no-color',
    '--no-cache-dir',
  ];

  static List<String> metadata(String url, {List<String> network = const []}) => [
        ...base,
        ...network,
        '--dump-single-json',
        '--flat-playlist',
        '--no-warnings',
        '--',
        url,
      ];

  /// `-f`/`-S` selection for the requested options.
  static List<String> formatSelection(DownloadOptions o) {
    if (o.isAudioOnly) {
      return [
        '-f', 'ba/b',
        '-x',
        if (o.audioFormat == AudioFormat.mp3) ...[
          '--audio-format', 'mp3',
          '--audio-quality', o.audioQuality.ytDlpValue,
        ] else ...[
          '--audio-format', 'best',
        ],
      ];
    }
    final sort = <String>[
      // Best stream at or below the requested short-side resolution; if none
      // exists yt-dlp falls back to the smallest one above it.
      if (o.quality.height != null) 'res:${o.quality.height}',
      if (o.container == ContainerFormat.mp4) 'ext:mp4:m4a',
    ];
    return [
      '-f', 'bv*+ba/b',
      if (sort.isNotEmpty) ...['-S', sort.join(',')],
      if (o.container.extension != null) ...[
        // Merge/remux without re-encoding.
        '--merge-output-format', o.container.extension!,
        '--remux-video', o.container.extension!,
      ],
    ];
  }

  /// Output template relative to `-P home:`; literal parts are escaped.
  static String outputTemplate({int? playlistIndex, bool numbered = false}) {
    final prefix = (numbered && playlistIndex != null)
        ? '${playlistIndex.toString().padLeft(3, '0')} - '
        : '';
    return '${PathUtils.escapeTemplate(prefix)}%(title).180B [%(id)s].%(ext)s';
  }

  static List<String> download({
    required String url,
    required DownloadOptions options,
    required String directory,
    required String outputTemplate,
    String? ffmpegLocation,
    List<String> network = const [],
  }) =>
      [
        ...base,
        ...network,
        '--newline',
        '--no-playlist',
        '--no-mtime',
        '--continue',
        '--no-overwrites',
        '--windows-filenames',
        '--quiet',
        '--progress',
        '--progress-delta', '0.5',
        '--progress-template',
        'download:$marker'
            'dl|%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|'
            '%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|'
            '%(progress.fragment_index)s|%(progress.fragment_count)s|%(info.format_id)s',
        '--progress-template',
        'postprocess:${marker}pp|%(progress.status)s|%(progress.postprocessor)s',
        '--print', 'before_dl:${marker}dest|%(filename)s',
        '--print', 'after_move:${marker}meta|%(height)s|%(width)s|%(ext)s',
        '--print', 'after_move:${marker}file|%(filepath)s',
        if (ffmpegLocation != null) ...['--ffmpeg-location', ffmpegLocation],
        '-P', 'home:$directory',
        '-o', outputTemplate,
        ...formatSelection(options),
        '--',
        url,
      ];
}
