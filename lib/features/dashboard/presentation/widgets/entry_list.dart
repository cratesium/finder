import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/media_info.dart';
import '../../../../widgets/common.dart';
import '../../../../widgets/status_chip.dart';
import '../../application/dashboard_controller.dart';

/// Selectable list of playlist entries, built lazily for large playlists.
class EntryListSliver extends ConsumerWidget {
  const EntryListSliver({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final selected = ref.watch(dashboardProvider.select((s) => s.selected));
    final selectable = info.downloadableCount;
    final selectedCount = info.entries.where((e) => selected.contains(e.id)).length;
    final allSelected = selectable > 0 && selectedCount == selectable;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(Gap.radiusLg)),
            ),
            child: Row(
              children: [
                Checkbox(
                  key: const Key('select-all'),
                  value: allSelected ? true : (selectedCount == 0 ? false : null),
                  tristate: true,
                  onChanged: selectable == 0
                      ? null
                      : (_) => ref.read(dashboardProvider.notifier).selectAll(!allSelected),
                ),
                const SizedBox(width: Gap.xs),
                Text(info.isPlaylist ? 'Videos' : 'Video', style: context.text.titleSmall),
                const SizedBox(width: Gap.sm),
                Text('$selectedCount of $selectable selected', style: context.text.bodySmall),
              ],
            ),
          ),
        ),
        SliverDecoratedBoxSliver(
          sliver: SliverList.builder(
            itemCount: info.entries.length,
            itemBuilder: (context, i) {
              final e = info.entries[i];
              return _EntryRow(
                entry: e,
                selected: selected.contains(e.id),
                isLast: i == info.entries.length - 1,
                onToggle: () => ref.read(dashboardProvider.notifier).toggle(e.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Draws side borders around the list rows.
class SliverDecoratedBoxSliver extends StatelessWidget {
  const SliverDecoratedBoxSliver({super.key, required this.sliver});
  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          left: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Gap.radiusLg)),
      ),
      sliver: sliver,
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.isLast,
    required this.onToggle,
  });

  final MediaEntry entry;
  final bool selected;
  final bool isLast;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final available = entry.availability.isDownloadable;
    final subtitle = [
      if (entry.uploader != null) entry.uploader!,
      if (!available) entry.availability.explanation,
    ].join(' · ');

    return InkWell(
      onTap: available ? onToggle : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        decoration: BoxDecoration(
          border: isLast ? null : Border(top: BorderSide(color: c.border.withValues(alpha: 0.6))),
        ),
        child: Opacity(
          opacity: available ? 1 : 0.55,
          child: Row(
            children: [
              Checkbox(value: selected && available, onChanged: available ? (_) => onToggle() : null),
              SizedBox(
                width: 36,
                child: Text(
                  entry.playlistIndex?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: context.text.labelMedium?.copyWith(
                      color: c.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(width: Gap.md),
              MediaThumbnail(url: entry.thumbnailUrl, width: 96, height: 54),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              if (!available)
                StatusChip(label: entry.availability.label, tone: ChipTone.warning)
              else
                Text(Fmt.duration(entry.duration),
                    style: context.text.labelMedium
                        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: Gap.sm),
            ],
          ),
        ),
      ),
    );
  }
}
