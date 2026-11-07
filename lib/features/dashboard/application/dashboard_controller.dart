import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/utils/url_validator.dart';
import '../../../models/download_options.dart';
import '../../../models/download_task.dart';
import '../../../models/media_info.dart';
import '../../../services/cancellation.dart';
import '../../downloads/application/download_providers.dart';
import '../../downloads/domain/download_manager.dart';
import '../../settings/application/dependency_controller.dart';
import '../../settings/application/settings_controller.dart';

final _log = Logger('dashboard');

sealed class DetectPhase {
  const DetectPhase();
}

class DetectIdle extends DetectPhase {
  const DetectIdle();
}

class DetectLoading extends DetectPhase {
  const DetectLoading(this.url);
  final String url;
}

class DetectLoaded extends DetectPhase {
  const DetectLoaded(this.info);
  final MediaInfo info;
}

class DetectFailed extends DetectPhase {
  const DetectFailed(this.error);
  final AppError error;
}

class DashboardState {
  const DashboardState({
    required this.options,
    this.url = '',
    this.phase = const DetectIdle(),
    this.selected = const {},
    this.urlError,
    this.enqueueing = false,
  });

  final String url;
  final DetectPhase phase;
  final Set<String> selected;
  final DownloadOptions options;
  final String? urlError;
  final bool enqueueing;

  MediaInfo? get info => switch (phase) {
        DetectLoaded(:final info) => info,
        _ => null,
      };

  List<MediaEntry> get selectedEntries =>
      info?.entries.where((e) => selected.contains(e.id) && e.availability.isDownloadable).toList() ??
      const [];

  /// Qualities offered in the UI. For a single video only resolutions that
  /// actually exist are enabled; for playlists, formats vary per video and are
  /// resolved at download time (best at or below the chosen value).
  Set<VideoQuality> get availableQualities {
    final i = info;
    if (i == null || i.isPlaylist) return VideoQuality.values.toSet();
    return i.entries.first.availableQualities;
  }

  DashboardState copyWith({
    String? url,
    DetectPhase? phase,
    Set<String>? selected,
    DownloadOptions? options,
    String? Function()? urlError,
    bool? enqueueing,
  }) =>
      DashboardState(
        url: url ?? this.url,
        phase: phase ?? this.phase,
        selected: selected ?? this.selected,
        options: options ?? this.options,
        urlError: urlError != null ? urlError() : this.urlError,
        enqueueing: enqueueing ?? this.enqueueing,
      );
}

class DashboardController extends Notifier<DashboardState> {
  CancellationToken? _token;

  @override
  DashboardState build() {
    ref.onDispose(() => _token?.cancel());
    // Follow the default folder from Settings unless the user picked another one here.
    ref.listen(settingsProvider, (prev, next) {
      if (prev != null && state.options.destinationDir == prev.downloadDirectory) {
        state = state.copyWith(
            options: state.options.copyWith(destinationDir: next.downloadDirectory));
      }
    });
    return DashboardState(options: ref.read(settingsProvider).defaultOptions());
  }

  void setUrl(String url) {
    state = state.copyWith(url: url, urlError: () => null);
  }

  Future<void> detect([String? url]) async {
    final raw = url ?? state.url;
    final validation = UrlValidator.validate(raw);
    if (validation is InvalidUrl) {
      state = state.copyWith(url: raw, urlError: () => validation.reason);
      return;
    }
    final normalized = (validation as ValidUrl).normalized;
    state = state.copyWith(url: normalized, urlError: () => null);

    _token?.cancel();
    final token = _token = CancellationToken();
    state = state.copyWith(phase: DetectLoading(normalized));

    try {
      final deps = await ref.read(dependencyProvider.future);
      if (!deps.ytDlp.isReady) {
        throw const AppError(AppErrorKind.missingDependency,
            'yt-dlp is required to read video information. Install it in Settings → Dependencies.');
      }
      final network = await ref.read(ytDlpNetworkProvider.future);
      final info = await ref
          .read(metadataServiceProvider)
          .fetch(normalized, ytDlpPath: deps.ytDlp.path!, cancel: token, network: network);
      if (token.isCancelled) return;
      if (info.entries.isEmpty) {
        throw const AppError(AppErrorKind.unavailable,
            'This playlist has no videos you can access.');
      }
      final selectable = info.entries
          .where((e) => e.availability.isDownloadable)
          .map((e) => e.id)
          .toSet();
      var options = state.options;
      if (!info.isPlaylist && !info.entries.first.availableQualities.contains(options.quality)) {
        options = options.copyWith(quality: VideoQuality.best);
      }
      state = state.copyWith(phase: DetectLoaded(info), selected: selectable, options: options);
    } on AppError catch (e) {
      if (token.isCancelled || e.kind == AppErrorKind.cancelled) {
        state = state.copyWith(phase: const DetectIdle());
        return;
      }
      _log.info('detect failed: ${e.kind.name}');
      state = state.copyWith(phase: DetectFailed(e));
    } catch (e, st) {
      _log.severe('unexpected detect failure', e, st);
      state = state.copyWith(phase: DetectFailed(AppError.of(AppErrorKind.unknown, detail: '$e')));
    }
  }

  void cancelDetect() {
    _token?.cancel();
    state = state.copyWith(phase: const DetectIdle());
  }

  void reset() {
    _token?.cancel();
    state = DashboardState(options: ref.read(settingsProvider).defaultOptions());
  }

  void toggle(String id) {
    final s = {...state.selected};
    if (!s.remove(id)) s.add(id);
    state = state.copyWith(selected: s);
  }

  void selectAll(bool value) {
    final info = state.info;
    if (info == null) return;
    state = state.copyWith(
      selected: value
          ? info.entries.where((e) => e.availability.isDownloadable).map((e) => e.id).toSet()
          : <String>{},
    );
  }

  void setOptions(DownloadOptions options) => state = state.copyWith(options: options);

  Future<EnqueueResult> enqueueSelected() async {
    final info = state.info;
    if (info == null) return const EnqueueResult();
    final entries = state.selectedEntries;
    state = state.copyWith(enqueueing: true);
    try {
      final requests = [
        for (final e in entries)
          DownloadRequest(
            entry: e,
            options: state.options,
            playlistTitle: info.isPlaylist ? info.title : null,
          ),
      ];
      return await ref.read(downloadManagerProvider).enqueue(requests);
    } finally {
      state = state.copyWith(enqueueing: false);
    }
  }
}

final dashboardProvider =
    NotifierProvider<DashboardController, DashboardState>(DashboardController.new);
