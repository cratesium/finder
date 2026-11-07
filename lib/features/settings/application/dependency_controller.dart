import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_error.dart';
import '../../../models/dependency_status.dart';
import '../../../services/trust_store_service.dart';
import 'settings_controller.dart';

/// Resolves yt-dlp and FFmpeg. Re-runs whenever custom paths change.
class DependencyController extends AsyncNotifier<DependencySnapshot> {
  @override
  Future<DependencySnapshot> build() {
    final paths = ref.watch(settingsProvider.select((s) => (s.ytDlpPath, s.ffmpegPath)));
    return ref.read(dependencyManagerProvider).snapshot(ytDlpPath: paths.$1, ffmpegPath: paths.$2);
  }

  Future<void> recheck() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Certificate configuration for yt-dlp, rebuilt when the setting changes.
final ytDlpNetworkProvider = FutureProvider<YtDlpNetworkConfig>((ref) {
  final useSystem = ref.watch(settingsProvider.select((s) => s.useSystemCertificates));
  return ref.read(trustStoreServiceProvider).build(useSystemCertificates: useSystem);
});

final dependencyProvider =
    AsyncNotifierProvider<DependencyController, DependencySnapshot>(DependencyController.new);

/// Progress of an install/update operation.
class InstallState {
  const InstallState({this.running = false, this.fraction, this.stage, this.error});
  final bool running;
  final double? fraction;
  final String? stage;
  final AppError? error;
}

class InstallController extends Notifier<Map<DependencyKind, InstallState>> {
  @override
  Map<DependencyKind, InstallState> build() => const {};

  Future<bool> install(DependencyKind kind) async {
    if (state[kind]?.running ?? false) return false;
    _set(kind, const InstallState(running: true, stage: 'Starting'));
    try {
      await ref.read(dependencyManagerProvider).install(kind, onProgress: (f, stage) {
        _set(kind, InstallState(running: true, fraction: f, stage: stage));
      });
      _set(kind, const InstallState());
      // Prefer the freshly installed copy over any custom path.
      final settings = ref.read(settingsProvider);
      final hasCustom = kind == DependencyKind.ytDlp ? settings.ytDlpPath != null : settings.ffmpegPath != null;
      if (hasCustom) {
        await ref.read(settingsProvider.notifier).change((s) => kind == DependencyKind.ytDlp
            ? s.copyWith(ytDlpPath: () => null)
            : s.copyWith(ffmpegPath: () => null));
      }
      await ref.read(dependencyProvider.notifier).recheck();
      return true;
    } on AppError catch (e) {
      _set(kind, InstallState(error: e));
      return false;
    } catch (e) {
      _set(kind, InstallState(error: AppError.of(AppErrorKind.unknown, detail: '$e')));
      return false;
    }
  }

  void _set(DependencyKind kind, InstallState s) => state = {...state, kind: s};
}

final installProvider =
    NotifierProvider<InstallController, Map<DependencyKind, InstallState>>(InstallController.new);
