import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/download_task.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/status_chip.dart';
import '../application/download_providers.dart';

/// Card showing a task's real progress and the actions valid for its state.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.queuePosition, this.showReorder = false});

  final DownloadTask task;
  final int? queuePosition;
  final bool showReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final manager = ref.read(downloadManagerProvider);
    final opener = ref.read(fileOpenerProvider);
    final p = task.progress;
    final s = task.status;

    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) showErrorToast(context, e);
      }
    }

    final stats = <String>[
      if (s == TaskStatus.completed || s == TaskStatus.skipped) ...[
        if (task.fileSize != null) Fmt.bytes(task.fileSize),
        if (task.actualResolution != null && !task.options.isAudioOnly) '${task.actualResolution}p',
        if (task.actualExtension != null) task.actualExtension!.toUpperCase(),
      ] else if (s.isActive || s == TaskStatus.paused) ...[
        if (p.downloadedBytes != null)
          p.totalBytes != null
              ? '${Fmt.bytes(p.downloadedBytes)} of ${p.totalBytesIsEstimate ? '~' : ''}${Fmt.bytes(p.totalBytes)}'
              : Fmt.bytes(p.downloadedBytes),
        if (s == TaskStatus.downloading && p.speed != null) Fmt.speed(p.speed),
        if (s == TaskStatus.downloading && p.etaSeconds != null) Fmt.eta(p.etaSeconds),
        if (p.fragmentCount != null && p.fragmentIndex != null) 'fragment ${p.fragmentIndex}/${p.fragmentCount}',
      ],
    ];

    final fraction = p.fraction;
    final showBar = s.isActive || s == TaskStatus.paused;

    return AppCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (queuePosition != null)
            SizedBox(
              width: 34,
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text('#$queuePosition',
                    style: context.text.labelMedium?.copyWith(
                        color: c.textTertiary, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          MediaThumbnail(url: task.entry.thumbnailUrl, width: 104, height: 58),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: Gap.sm),
                    StatusChip.task(s),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (task.request.playlistTitle != null) task.request.playlistTitle!,
                    task.options.summary,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
                if (showBar) ...[
                  const SizedBox(height: Gap.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: s == TaskStatus.processing || s == TaskStatus.preparing ? null : fraction,
                      color: s == TaskStatus.paused ? c.warning : c.accent,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (p.phaseLabel != null && (s.isActive || s == TaskStatus.paused)) ...[
                      Text(p.phaseLabel!, style: context.text.labelMedium?.copyWith(color: c.textSecondary)),
                      if (stats.isNotEmpty) Text('  ·  ', style: context.text.labelMedium),
                    ],
                    Expanded(
                      child: Text(
                        stats.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium
                            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                    if (showBar && fraction != null)
                      Text(Fmt.percent(fraction),
                          style: context.text.labelMedium?.copyWith(
                              color: c.textPrimary, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
                if (task.error != null) ...[
                  const SizedBox(height: 6),
                  Text(task.error!.message,
                      style: context.text.bodySmall?.copyWith(color: c.danger)),
                ],
                if (task.notice != null) ...[
                  const SizedBox(height: 6),
                  Text(task.notice!, style: context.text.bodySmall?.copyWith(color: c.warning)),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Wrap(
            spacing: 2,
            children: [
              if (showReorder && s == TaskStatus.queued) ...[
                IconButton(
                  tooltip: 'Move to top',
                  onPressed: () => manager.moveToTop(task.id),
                  icon: const Icon(Icons.vertical_align_top_rounded),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: () => manager.move(task.id, -1),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: () => manager.move(task.id, 1),
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
              ],
              if (s.isActive || s == TaskStatus.queued)
                IconButton(
                  tooltip: s == TaskStatus.queued ? 'Hold' : 'Pause (keeps partial data)',
                  onPressed: () => guard(() => manager.pause(task.id)),
                  icon: const Icon(Icons.pause_rounded),
                ),
              if (s == TaskStatus.paused)
                IconButton(
                  tooltip: 'Resume',
                  onPressed: () => manager.resume(task.id),
                  icon: Icon(Icons.play_arrow_rounded, color: c.accent),
                ),
              if (s == TaskStatus.failed || s == TaskStatus.cancelled)
                IconButton(
                  tooltip: 'Retry',
                  onPressed: () => manager.retry(task.id),
                  icon: Icon(Icons.refresh_rounded, color: c.accent),
                ),
              if ((s == TaskStatus.completed || s == TaskStatus.skipped) && task.filePath != null) ...[
                IconButton(
                  tooltip: 'Open file',
                  onPressed: () => guard(() => opener.openFile(task.filePath!)),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Show in folder',
                  onPressed: () => guard(() => opener.revealInFolder(task.filePath!)),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
              if (!s.isTerminal)
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => guard(() => manager.cancel(task.id)),
                  icon: const Icon(Icons.close_rounded),
                )
              else
                IconButton(
                  tooltip: 'Remove from list',
                  onPressed: () => guard(() => manager.remove(task.id)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
