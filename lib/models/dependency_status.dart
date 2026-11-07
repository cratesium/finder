enum DependencyKind {
  ytDlp('yt-dlp', 'yt-dlp'),
  ffmpeg('FFmpeg', 'ffmpeg');

  const DependencyKind(this.label, this.executableBase);
  final String label;
  final String executableBase;
}

enum DependencySource {
  custom('Custom path'),
  managed('Installed by CourseGrab'),
  bundled('Bundled with app'),
  system('System');

  const DependencySource(this.label);
  final String label;
}

enum DependencyState { ready, missing, invalid }

class DependencyStatus {
  const DependencyStatus({
    required this.kind,
    required this.state,
    this.path,
    this.version,
    this.source,
    this.message,
  });

  const DependencyStatus.missing(this.kind, {this.message})
      : state = DependencyState.missing,
        path = null,
        version = null,
        source = null;

  final DependencyKind kind;
  final DependencyState state;
  final String? path;
  final String? version;
  final DependencySource? source;
  final String? message;

  bool get isReady => state == DependencyState.ready && path != null;
}

/// Snapshot of both required tools.
class DependencySnapshot {
  const DependencySnapshot({required this.ytDlp, required this.ffmpeg});

  final DependencyStatus ytDlp;
  final DependencyStatus ffmpeg;

  bool get allReady => ytDlp.isReady && ffmpeg.isReady;

  DependencyStatus of(DependencyKind kind) =>
      kind == DependencyKind.ytDlp ? ytDlp : ffmpeg;
}
