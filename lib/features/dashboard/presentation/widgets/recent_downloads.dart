import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/history_record.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/brand.dart';
import '../../../../widgets/common.dart';
import '../../../../widgets/feedback.dart';
import '../../../../widgets/status_chip.dart';
import '../../../downloads/application/download_providers.dart';
import '../../../history/application/history_controller.dart';

/// Latest few history records, refreshed as downloads finish.
final recentHistoryProvider = FutureProvider<List<HistoryRecord>>((ref) async {
  ref.watch(historyRevisionProvider);
  ref.watch(tasksProvider.select((ts) => ts.where((t) => t.status.isTerminal).length));
  final records = await ref.read(historyRepositoryProvider).query(const HistoryQuery());
  return markMissingFiles(records.take(5).toList());
});

/// "In progress" strip plus the most recent downloads.
class RecentDownloadsSection extends ConsumerWidget {
  const RecentDownloadsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final active = tasks.where((t) => t.status.isActive).toList();
    final queued = tasks.where((t) => t.status.isWaiting).length;
    final recent = ref.watch(recentHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active.isNotEmpty || queued > 0) ...[
          _InProgressCard(activeCount: active.length, queued: queued, fraction: _overall(active)),
          const SizedBox(height: Gap.lg),
        ],
        AppCard(
          padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xl, Gap.sm, Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.xs, Gap.sm),
                child: CardHeader(
                  'Recent downloads',
                  trailing: TextButton(
                    onPressed: () => context.go(Routes.history),
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.card.textSecondary,
                      textStyle: AppTheme.card().textTheme.labelLarge?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('See all'),
                  ),
                ),
              ),
              recent.when(
                loading: () => const SizedBox(height: 80),
                error: (_, _) => const SizedBox.shrink(),
                data: (records) => records.isEmpty
                    ? const EmptyState(
                        icon: Icons.video_library_outlined,
                        title: 'No downloads yet',
                        message: 'Your finished downloads will appear here.',
                      )
                    : Column(
                        children: [
                          for (final (i, r) in records.indexed) ...[
                            if (i > 0)
                              Divider(height: 1, indent: Gap.lg, endIndent: Gap.lg, color: AppPalette.card.border),
                            _RecentRow(record: r),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static double? _overall(List active) {
    final fractions = active.map((t) => t.progress.fraction as double?).whereType<double>().toList();
    if (fractions.isEmpty) return null;
    return fractions.reduce((a, b) => a + b) / fractions.length;
  }
}

class _InProgressCard extends StatelessWidget {
  const _InProgressCard({required this.activeCount, required this.queued, required this.fraction});
  final int activeCount;
  final int queued;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return CardScope(
      builder: (context) {
        final c = context.palette;
        return AppCard(
          borderColor: AppPalette.card.accent.withValues(alpha: 0.35),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: BorderRadius.circular(Gap.radiusMd)),
                child: Icon(Icons.downloading_rounded, color: c.onAccent, size: 20),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (activeCount > 0) '${Fmt.plural(activeCount, 'download')} in progress',
                        if (queued > 0) '$queued queued',
                      ].join(' · '),
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: Gap.sm),
                    BrandProgressBar(value: activeCount == 0 ? 0 : fraction, height: 5),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              TextButton(onPressed: () => context.go(Routes.downloads), child: const Text('View')),
            ],
          ),
        );
      },
    );
  }
}

class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.record});
  final HistoryRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    final opener = ref.read(fileOpenerProvider);
    final canOpen = r.status == HistoryStatus.completed && r.filePath != null && !r.fileMissing;
    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) showErrorToast(context, e);
      }
    }

    final meta = [
      if (r.playlistTitle != null) r.playlistTitle!,
      if (r.resolution != null) r.resolution!,
      if (r.fileSize != null) Fmt.bytes(r.fileSize),
      Fmt.date(r.completedAt ?? r.createdAt),
    ].join(' · ');

    return InkWell(
      onTap: canOpen ? () => guard(() => opener.openFile(r.filePath!)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm + 2),
        child: Row(
          children: [
            MediaThumbnail(url: r.thumbnailUrl, width: 80, height: 45, radius: Gap.radiusSm),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            if (r.fileMissing)
              const StatusChip(label: 'Missing', tone: ChipTone.warning)
            else
              StatusChip.history(r.status),
            if (canOpen)
              IconButton(
                tooltip: 'Show in folder',
                onPressed: () => guard(() => opener.revealInFolder(r.filePath!)),
                icon: const Icon(Icons.folder_open_outlined),
              ),
          ],
        ),
      ),
    );
  }
}
