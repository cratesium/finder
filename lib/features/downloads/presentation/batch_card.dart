import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/download_task.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/brand.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/status_chip.dart';
import '../application/download_providers.dart';
import '../domain/download_batches.dart';
import 'task_tile.dart';

/// One playlist download: overall progress, per-state counts, bulk actions,
/// a summary when it's done, and the individual items on demand.
class BatchCard extends ConsumerStatefulWidget {
  const BatchCard({super.key, required this.batch});
  final DownloadBatch batch;

  @override
  ConsumerState<BatchCard> createState() => _BatchCardState();
}

class _BatchCardState extends ConsumerState<BatchCard> {
  bool? _expanded;

  Future<void> _each(Iterable<DownloadTask> tasks, Future<void> Function(String id) action) async {
    try {
      for (final t in tasks.toList()) {
        await action(t.id);
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardScope(
      builder: (context) {
        final c = context.palette;
        final b = widget.batch;
        final manager = ref.read(downloadManagerProvider);
        // Expanded while running, collapsed to the summary once finished.
        final expanded = _expanded ?? !b.isFinished;
        final speed = b.speed;
        final cover = b.tasks.first.entry.thumbnailUrl;

        final chips = <Widget>[
          if (b.active > 0) StatusChip(label: '${b.active} downloading', tone: ChipTone.accent),
          if (b.pending > 0) StatusChip(label: '${b.pending} pending', tone: ChipTone.info),
          if (b.paused > 0) StatusChip(label: '${b.paused} paused', tone: ChipTone.warning),
          if (b.completed > 0) StatusChip(label: '${b.completed} completed', tone: ChipTone.success),
          if (b.skipped > 0) StatusChip(label: '${b.skipped} skipped', tone: ChipTone.neutral),
          if (b.failed > 0) StatusChip(label: '${b.failed} failed', tone: ChipTone.danger),
          if (b.cancelled > 0) StatusChip(label: '${b.cancelled} cancelled', tone: ChipTone.neutral),
        ];

        final actions = <Widget>[
          if (b.hasRunnable)
            IconButton(
              tooltip: 'Pause playlist',
              onPressed: () =>
                  _each(b.tasks.where((t) => t.status.isActive || t.status == TaskStatus.queued), manager.pause),
              icon: const Icon(Icons.pause_rounded),
            ),
          if (b.paused > 0)
            IconButton(
              tooltip: 'Resume playlist',
              onPressed: () => _each(b.tasks.where((t) => t.status == TaskStatus.paused), (id) async {
                manager.resume(id);
              }),
              icon: Icon(Icons.play_arrow_rounded, color: c.accent),
            ),
          if (b.hasRetryable)
            IconButton(
              tooltip: 'Retry failed and cancelled',
              onPressed: () => _each(
                b.tasks.where((t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled),
                (id) async => manager.retry(id),
              ),
              icon: Icon(Icons.refresh_rounded, color: c.accent),
            ),
          if (!b.isFinished)
            IconButton(
              tooltip: 'Cancel playlist',
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Cancel this playlist?',
                  message:
                      'Stops ${b.total - b.completed - b.skipped} unfinished item(s) and removes their partial files. '
                      'Finished videos are kept.',
                  confirmLabel: 'Cancel downloads',
                  destructive: true,
                );
                if (ok) await _each(b.tasks.where((t) => !t.status.isTerminal), manager.cancel);
              },
              icon: const Icon(Icons.close_rounded),
            )
          else
            IconButton(
              tooltip: 'Remove from list',
              onPressed: () => _each(b.tasks, manager.remove),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: expanded ? 'Hide videos' : 'Show videos',
            onPressed: () => setState(() => _expanded = !expanded),
            icon: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: Motion.medium,
              child: const Icon(Icons.expand_more_rounded),
            ),
          ),
        ];

        return AppCard(
          padding: const EdgeInsets.all(Gap.md),
          borderColor: b.isFinished ? null : AppPalette.card.accent.withValues(alpha: 0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      MediaThumbnail(url: cover, width: 104, height: 58, radius: Gap.radiusSm),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.playlist_play_rounded, size: 12, color: Colors.white),
                              const SizedBox(width: 2),
                              Text(
                                '${b.total}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          b.isFinished
                              ? 'Playlist finished · ${b.summary}'
                              : 'Playlist · ${b.completed + b.skipped} of ${b.total} done'
                                    '${speed != null ? '  ·  ${Fmt.speed(speed)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                        const SizedBox(height: Gap.sm),
                        Row(
                          children: [
                            Expanded(
                              child: BrandProgressBar(
                                value: b.fraction,
                                color: b.isFinished && b.failed > 0 ? c.warning : null,
                              ),
                            ),
                            const SizedBox(width: Gap.sm),
                            Text(
                              Fmt.percent(b.fraction),
                              style: context.text.labelMedium?.copyWith(
                                color: c.textPrimary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Wrap(spacing: 2, children: actions),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
              if (b.isFinished) ...[
                const SizedBox(height: Gap.md),
                InlineBanner(
                  tone: b.failed > 0 ? BannerTone.warning : BannerTone.success,
                  title: b.failed > 0 ? 'Playlist finished with errors' : 'Playlist downloaded',
                  message: b.summary,
                ),
              ],
              AnimatedSize(
                duration: Motion.medium,
                curve: Motion.curve,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: Gap.md),
                        child: Column(
                          children: [
                            for (final t in b.tasks) ...[
                              TaskTile(key: ValueKey(t.id), task: t, dense: true),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }
}
