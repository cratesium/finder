import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../models/download_task.dart';
import '../../settings/application/dependency_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../domain/download_manager.dart';

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final settings = ref.read(settingsProvider);
  final manager = DownloadManager(
    downloader: ref.watch(downloaderServiceProvider),
    history: ref.watch(historyRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
    maxConcurrent: settings.maxConcurrentDownloads,
    skipCompleted: settings.skipCompleted,
    notificationsEnabled: settings.notificationsEnabled,
    resolutionProbe: (ffmpeg, file) async =>
        (await ref.read(ffmpegServiceProvider).probe(ffmpeg, file))?.res,
    tools: () async {
      final snap = await ref.read(dependencyProvider.future);
      return ResolvedTools(
        ytDlpPath: snap.ytDlp.isReady ? snap.ytDlp.path : null,
        ffmpegPath: snap.ffmpeg.isReady ? snap.ffmpeg.path : null,
        network: await ref.read(ytDlpNetworkProvider.future),
      );
    },
  );
  ref.listen(settingsProvider, (_, next) {
    manager
      ..maxConcurrent = next.maxConcurrentDownloads
      ..skipCompleted = next.skipCompleted
      ..notificationsEnabled = next.notificationsEnabled;
  });
  ref.onDispose(manager.shutdown);
  return manager;
});

/// Live list of tasks, updated from the manager's change stream.
class TasksController extends Notifier<List<DownloadTask>> {
  @override
  List<DownloadTask> build() {
    final manager = ref.watch(downloadManagerProvider);
    final sub = manager.changes.listen((tasks) => state = tasks);
    ref.onDispose(sub.cancel);
    return manager.tasks;
  }
}

final tasksProvider = NotifierProvider<TasksController, List<DownloadTask>>(TasksController.new);

final activeTaskCountProvider = Provider<int>(
    (ref) => ref.watch(tasksProvider).where((t) => t.status.isActive).length);

final queuedTaskCountProvider = Provider<int>(
    (ref) => ref.watch(tasksProvider).where((t) => t.status == TaskStatus.queued).length);
