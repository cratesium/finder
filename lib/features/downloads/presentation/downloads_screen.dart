import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/download_task.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/page_scaffold.dart';
import '../application/download_providers.dart';
import 'task_tile.dart';

enum _Filter { all, active, completed, failed }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _Filter _filter = _Filter.all;

  static bool _matches(_Filter filter, DownloadTask t) => switch (filter) {
        _Filter.all => true,
        _Filter.active => t.status.isActive || t.status == TaskStatus.paused,
        _Filter.completed => t.status == TaskStatus.completed || t.status == TaskStatus.skipped,
        _Filter.failed => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled,
      };

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tasksProvider).where((t) => t.status != TaskStatus.queued).toList();
    // Active first, then most recently finished.
    all.sort((a, b) {
      int rank(DownloadTask t) => t.status.isActive ? 0 : (t.status == TaskStatus.paused ? 1 : 2);
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (b.finishedAt ?? b.startedAt ?? b.createdAt).compareTo(a.finishedAt ?? a.startedAt ?? a.createdAt);
    });
    final visible = all.where((t) => _matches(_filter, t)).toList();
    final counts = {for (final f in _Filter.values) f: all.where((t) => _matches(f, t)).length};
    final hasFinished = all.any((t) =>
        t.status == TaskStatus.completed || t.status == TaskStatus.skipped || t.status == TaskStatus.cancelled);

    return PageScaffold(
      title: 'Downloads',
      subtitle: 'Live progress reported by yt-dlp for this session.',
      actions: [
        OutlinedButton.icon(
          onPressed: hasFinished ? () => ref.read(downloadManagerProvider).clearFinished() : null,
          icon: const Icon(Icons.clear_all_rounded, size: 17),
          label: const Text('Clear finished'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [
                for (final f in _Filter.values)
                  ButtonSegment(
                    value: f,
                    label: Text('${switch (f) {
                      _Filter.all => 'All',
                      _Filter.active => 'Active',
                      _Filter.completed => 'Completed',
                      _Filter.failed => 'Failed',
                    }} ${counts[f]}'),
                  ),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (visible.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.download_outlined,
                title: all.isEmpty ? 'No downloads yet' : 'Nothing here',
                message: all.isEmpty
                    ? 'Detect a video or playlist on the Dashboard and choose what to download.'
                    : 'No downloads match this filter.',
                action: all.isEmpty
                    ? FilledButton(
                        onPressed: () => context.go(Routes.dashboard),
                        child: const Text('Go to Dashboard'),
                      )
                    : null,
              ),
            )
          else
            for (final t in visible) ...[
              TaskTile(key: ValueKey(t.id), task: t),
              const SizedBox(height: Gap.sm),
            ],
        ],
      ),
    );
  }
}
