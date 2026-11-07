import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/download_task.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/page_scaffold.dart';
import '../../downloads/application/download_providers.dart';
import '../../downloads/presentation/task_tile.dart';
import '../../settings/application/settings_controller.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final tasks = ref.watch(tasksProvider);
    final manager = ref.read(downloadManagerProvider);
    final waiting = tasks.where((t) => t.status == TaskStatus.queued).toList();
    final running = tasks.where((t) => t.status.isActive).length;
    final concurrency = ref.watch(settingsProvider.select((s) => s.maxConcurrentDownloads));
    final paused = manager.queuePaused;

    return PageScaffold(
      title: 'Queue',
      subtitle: 'Waiting downloads start automatically in this order.',
      actions: [
        if (waiting.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Remove all waiting downloads?',
                  message: 'This removes ${waiting.length} waiting item(s) from the queue. Active downloads keep running.',
                  confirmLabel: 'Remove',
                  destructive: true);
              if (!ok) return;
              for (final t in waiting) {
                await manager.cancel(t.id);
                await manager.remove(t.id);
              }
            },
            icon: const Icon(Icons.playlist_remove_rounded, size: 17),
            label: const Text('Clear queue'),
          ),
        FilledButton.icon(
          onPressed: () => manager.queuePaused = !paused,
          icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 17),
          label: Text(paused ? 'Resume queue' : 'Pause queue'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Wrap(
              spacing: Gap.xxl,
              runSpacing: Gap.lg,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Stat(label: 'Running', value: '$running / $concurrency'),
                _Stat(label: 'Waiting', value: '${waiting.length}'),
                _Stat(
                  label: 'Queue',
                  value: paused ? 'Paused' : 'Active',
                  color: paused ? c.warning : c.success,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Concurrent downloads', style: context.text.labelMedium),
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
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (paused)
            const Padding(
              padding: EdgeInsets.only(bottom: Gap.lg),
              child: InlineBanner(
                tone: BannerTone.warning,
                message: 'The queue is paused. Running downloads continue, but no new ones will start.',
              ),
            ),
          if (waiting.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.queue_outlined,
                title: 'The queue is empty',
                message: 'Items you add from the Dashboard wait here until a download slot is free.',
              ),
            )
          else
            for (final t in waiting) ...[
              TaskTile(
                key: ValueKey(t.id),
                task: t,
                queuePosition: manager.queuePosition(t.id),
                showReorder: true,
              ),
              const SizedBox(height: Gap.sm),
            ],
        ],
      ),
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
        Text(value, style: context.text.titleLarge?.copyWith(color: color)),
      ],
    );
  }
}
