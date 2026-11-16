import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/download_task.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/brand.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/page_scaffold.dart';
import '../../settings/application/settings_controller.dart';
import '../application/download_providers.dart';
import '../domain/download_batches.dart';
import 'batch_card.dart';
import 'task_tile.dart';

enum DownloadTab {
  all('All'),
  active('Downloading'),
  queued('Queued'),
  completed('Completed'),
  failed('Failed'),
  cancelled('Cancelled');

  const DownloadTab(this.label);
  final String label;

  bool matches(DownloadTask t) => switch (this) {
    all => true,
    active => t.status.isActive || t.status == TaskStatus.paused,
    queued => t.status == TaskStatus.queued,
    completed => t.status == TaskStatus.completed || t.status == TaskStatus.skipped,
    failed => t.status == TaskStatus.failed,
    cancelled => t.status == TaskStatus.cancelled,
  };

  static DownloadTab parse(String? name) =>
      DownloadTab.values.firstWhere((t) => t.name == name, orElse: () => DownloadTab.all);
}

/// Download management: live progress, queue, playlist batches and results.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  late DownloadTab _tab = DownloadTab.parse(widget.initialTab);

  @override
  void didUpdateWidget(covariant DownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab && widget.initialTab != null) {
      _tab = DownloadTab.parse(widget.initialTab);
    }
  }

  /// Running first, then paused, queued (in queue order), then most recent.
  static List<DownloadTask> _sorted(List<DownloadTask> tasks) {
    int rank(DownloadTask t) => t.status.isActive
        ? 0
        : t.status == TaskStatus.paused
        ? 1
        : t.status == TaskStatus.queued
        ? 2
        : 3;
    final indexed = tasks.indexed.toList();
    indexed.sort((a, b) {
      final r = rank(a.$2).compareTo(rank(b.$2));
      if (r != 0) return r;
      if (rank(a.$2) == 2) return a.$1.compareTo(b.$1);
      final ta = a.$2.finishedAt ?? a.$2.startedAt ?? a.$2.createdAt;
      final tb = b.$2.finishedAt ?? b.$2.startedAt ?? b.$2.createdAt;
      return tb.compareTo(ta);
    });
    return [for (final e in indexed) e.$2];
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final manager = ref.read(downloadManagerProvider);
    final counts = {for (final t in DownloadTab.values) t: tasks.where(t.matches).length};
    final visible = _sorted(tasks.where(_tab.matches).toList());
    final hasFinished = tasks.any((t) => t.status.isTerminal);
    final waiting = tasks.where((t) => t.status == TaskStatus.queued).toList();

    // In "All", a playlist's items are grouped into one card.
    final items = _tab == DownloadTab.all ? groupIntoBatches(visible) : visible.map(SingleItem.new).toList();

    return PageScaffold(
      title: 'Downloads',
      subtitle: 'Live progress, queue and results for this session.',
      actions: [
        if (waiting.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Remove all queued downloads?',
                message: 'This removes ${waiting.length} queued item(s). Downloads in progress keep running.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (!ok) return;
              for (final t in waiting) {
                await manager.cancel(t.id);
                await manager.remove(t.id);
              }
            },
            icon: const Icon(Icons.playlist_remove_rounded, size: 17),
            label: const Text('Clear queue'),
          ),
        OutlinedButton.icon(
          onPressed: hasFinished ? manager.clearFinished : null,
          icon: const Icon(Icons.clear_all_rounded, size: 17),
          label: const Text('Clear finished'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _QueueOverview(),
          const SizedBox(height: Gap.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PillSelector<DownloadTab>(
              value: _tab,
              items: DownloadTab.values,
              labelOf: (t) => t.label,
              countOf: (t) => counts[t],
              keyOf: (t) => Key('tab-${t.name}'),
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (visible.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.downloading_rounded,
                title: tasks.isEmpty ? 'No downloads yet' : 'Nothing here',
                message: tasks.isEmpty
                    ? 'Paste a video or playlist link on Home and choose what to download.'
                    : 'No downloads are ${_tab.label.toLowerCase()} right now.',
                action: tasks.isEmpty
                    ? GradientButton(
                        label: 'Go to Home',
                        icon: Icons.home_rounded,
                        onPressed: () => context.go(Routes.home),
                      )
                    : null,
              ),
            )
          else
            for (final item in items) ...[
              switch (item) {
                SingleItem(:final task) => TaskTile(
                  key: ValueKey(task.id),
                  task: task,
                  queuePosition: task.status == TaskStatus.queued ? manager.queuePosition(task.id) : null,
                  showReorder: _tab == DownloadTab.queued,
                ),
                BatchItem(:final batch) => BatchCard(key: ValueKey(batch.id), batch: batch),
              },
              const SizedBox(height: Gap.sm),
            ],
        ],
      ),
    );
  }
}

/// Running/queued/finished counts, queue pause and concurrency control.
class _QueueOverview extends ConsumerWidget {
  const _QueueOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardScope(
      builder: (context) {
        final c = context.palette;
        final tasks = ref.watch(tasksProvider);
        final manager = ref.read(downloadManagerProvider);
        final running = tasks.where((t) => t.status.isActive).length;
        final queued = tasks.where((t) => t.status == TaskStatus.queued).length;
        final done = tasks.where((t) => t.status == TaskStatus.completed || t.status == TaskStatus.skipped).length;
        final failed = tasks.where((t) => t.status == TaskStatus.failed).length;
        final concurrency = ref.watch(settingsProvider.select((s) => s.maxConcurrentDownloads));
        final paused = manager.queuePaused;

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Gap.xxl,
                runSpacing: Gap.lg,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Stat(label: 'Running', value: '$running / $concurrency', color: running > 0 ? c.accent : null),
                  _Stat(label: 'Queued', value: '$queued', color: queued > 0 ? c.info : null),
                  _Stat(label: 'Completed', value: '$done', color: done > 0 ? c.success : null),
                  _Stat(label: 'Failed', value: '$failed', color: failed > 0 ? c.danger : null),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Simultaneous downloads', style: context.text.labelMedium),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: concurrency.toDouble(),
                                min: 1,
                                max: AppConfig.maxConcurrentLimit.toDouble(),
                                divisions: AppConfig.maxConcurrentLimit - 1,
                                label: '$concurrency',
                                onChanged: (v) => ref
                                    .read(settingsProvider.notifier)
                                    .change((s) => s.copyWith(maxConcurrentDownloads: v.round())),
                              ),
                            ),
                            Text('$concurrency', style: context.text.titleSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => manager.queuePaused = !paused,
                    icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 17),
                    label: Text(paused ? 'Resume queue' : 'Pause queue'),
                  ),
                ],
              ),
              if (paused) ...[
                const SizedBox(height: Gap.md),
                const InlineBanner(
                  tone: BannerTone.warning,
                  message: 'The queue is paused. Downloads in progress continue, but no new ones will start.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.text.labelMedium),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.text.titleLarge?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
