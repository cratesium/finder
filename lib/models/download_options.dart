/// Target video quality. [height] is the short-side resolution in pixels.
enum VideoQuality {
  best(null, 'Best available'),
  p2160(2160, '2160p · 4K'),
  p1440(1440, '1440p'),
  p1080(1080, '1080p'),
  p720(720, '720p'),
  p480(480, '480p'),
  p360(360, '360p');

  const VideoQuality(this.height, this.label);
  final int? height;
  final String label;

  /// Maps a stream resolution to the preset it satisfies, tolerating small
  /// deviations (e.g. 1076p is treated as 1080p).
  static VideoQuality? bucketFor(int res) {
    for (final q in values) {
      final h = q.height;
      if (h == null) continue;
      if (res >= (h * 0.95).floor()) return q;
    }
    return null;
  }

  static VideoQuality fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => VideoQuality.best);
}

enum ContainerFormat {
  mp4('MP4', 'mp4'),
  mkv('MKV', 'mkv'),
  original('Original container', null);

  const ContainerFormat(this.label, this.extension);
  final String label;
  final String? extension;

  static ContainerFormat fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ContainerFormat.mp4);
}

enum DownloadMode {
  video('Video + audio'),
  audioOnly('Audio only');

  const DownloadMode(this.label);
  final String label;

  static DownloadMode fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => DownloadMode.video);
}

enum AudioFormat {
  original('Best available (no re-encode)'),
  mp3('MP3 (re-encoded)');

  const AudioFormat(this.label);
  final String label;

  static AudioFormat fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => AudioFormat.original);
}

enum AudioQuality {
  best('Best (VBR V0)', '0'),
  k320('320 kbps', '320K'),
  k192('192 kbps', '192K'),
  k128('128 kbps', '128K');

  const AudioQuality(this.label, this.ytDlpValue);
  final String label;
  final String ytDlpValue;

  static AudioQuality fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => AudioQuality.best);
}

/// Everything needed to describe how a single item should be downloaded.
class DownloadOptions {
  const DownloadOptions({
    required this.destinationDir,
    this.mode = DownloadMode.video,
    this.quality = VideoQuality.best,
    this.container = ContainerFormat.mp4,
    this.audioFormat = AudioFormat.original,
    this.audioQuality = AudioQuality.best,
    this.numberPlaylistItems = true,
  });

  final String destinationDir;
  final DownloadMode mode;
  final VideoQuality quality;
  final ContainerFormat container;
  final AudioFormat audioFormat;
  final AudioQuality audioQuality;
  final bool numberPlaylistItems;

  bool get isAudioOnly => mode == DownloadMode.audioOnly;

  /// Whether FFmpeg is needed to fulfil these options.
  ///
  /// Video downloads merge separate streams; audio extraction and remuxing
  /// also use FFmpeg.
  bool get requiresFfmpeg => true;

  /// The output "kind" used for duplicate detection: the same video into the
  /// same folder with the same output type is considered a duplicate.
  String get outputKind => isAudioOnly
      ? 'audio-${audioFormat.name}'
      : 'video-${container.name}';

  String get summary {
    if (isAudioOnly) {
      return audioFormat == AudioFormat.mp3
          ? 'Audio · MP3 ${audioQuality.label}'
          : 'Audio · best original';
    }
    return '${quality.label} · ${container.label}';
  }

  DownloadOptions copyWith({
    String? destinationDir,
    DownloadMode? mode,
    VideoQuality? quality,
    ContainerFormat? container,
    AudioFormat? audioFormat,
    AudioQuality? audioQuality,
    bool? numberPlaylistItems,
  }) =>
      DownloadOptions(
        destinationDir: destinationDir ?? this.destinationDir,
        mode: mode ?? this.mode,
        quality: quality ?? this.quality,
        container: container ?? this.container,
        audioFormat: audioFormat ?? this.audioFormat,
        audioQuality: audioQuality ?? this.audioQuality,
        numberPlaylistItems: numberPlaylistItems ?? this.numberPlaylistItems,
      );

  Map<String, Object?> toJson() => {
        'destinationDir': destinationDir,
        'mode': mode.name,
        'quality': quality.name,
        'container': container.name,
        'audioFormat': audioFormat.name,
        'audioQuality': audioQuality.name,
        'numberPlaylistItems': numberPlaylistItems,
      };

  factory DownloadOptions.fromJson(Map<String, Object?> json) => DownloadOptions(
        destinationDir: json['destinationDir'] as String? ?? '',
        mode: DownloadMode.fromName(json['mode'] as String?),
        quality: VideoQuality.fromName(json['quality'] as String?),
        container: ContainerFormat.fromName(json['container'] as String?),
        audioFormat: AudioFormat.fromName(json['audioFormat'] as String?),
        audioQuality: AudioQuality.fromName(json['audioQuality'] as String?),
        numberPlaylistItems: json['numberPlaylistItems'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is DownloadOptions &&
      other.destinationDir == destinationDir &&
      other.mode == mode &&
      other.quality == quality &&
      other.container == container &&
      other.audioFormat == audioFormat &&
      other.audioQuality == audioQuality &&
      other.numberPlaylistItems == numberPlaylistItems;

  @override
  int get hashCode => Object.hash(destinationDir, mode, quality, container,
      audioFormat, audioQuality, numberPlaylistItems);
}
