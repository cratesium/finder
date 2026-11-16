import '../../models/dependency_status.dart';
import '../binary_installer.dart';
import '../dependency_manager.dart';
import 'android_toolchain.dart';

/// Android ships yt-dlp and FFmpeg in the APK; startup [AndroidToolchain.ensureReady]
/// is the only prep step — no probing or desktop-style dependency UI.
class AndroidDependencyManager extends DependencyManager {
  AndroidDependencyManager({
    required super.platform,
    required super.processes,
    required super.managedBinDir,
    required this.toolchain,
  });

  final AndroidToolchain toolchain;

  static const _version = 'Built-in';

  DependencyStatus _ready(DependencyKind kind) => DependencyStatus(
    kind: kind,
    state: DependencyState.ready,
    path: kind == DependencyKind.ytDlp ? AndroidBundled.ytDlpPath : AndroidBundled.ffmpegPath,
    version: _version,
    source: DependencySource.bundled,
  );

  @override
  Future<DependencySnapshot> snapshot({String? ytDlpPath, String? ffmpegPath}) async =>
      DependencySnapshot(ytDlp: _ready(DependencyKind.ytDlp), ffmpeg: _ready(DependencyKind.ffmpeg));

  @override
  Future<DependencyStatus> resolve(DependencyKind kind, {String? customPath}) async => _ready(kind);

  @override
  Future<DependencyStatus> validate(DependencyKind kind, String path, DependencySource source) async => _ready(kind);

  @override
  bool canInstall(DependencyKind kind) => false;

  @override
  bool canUpdate(DependencyStatus status) => status.kind == DependencyKind.ytDlp && status.isReady;

  @override
  String guidance(DependencyKind kind) =>
      'Finder for Android includes yt-dlp and FFmpeg. There is nothing to install.';

  @override
  Future<DependencyStatus> install(DependencyKind kind, {InstallProgress? onProgress}) async {
    if (kind != DependencyKind.ytDlp) return _ready(kind);
    onProgress?.call(null, 'Updating yt-dlp');
    await toolchain.updateYtDlp();
    return _ready(kind);
  }
}