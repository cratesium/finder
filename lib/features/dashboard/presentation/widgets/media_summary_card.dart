import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/download_options.dart';
import '../../../../models/media_info.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/common.dart';
import '../../../../widgets/status_chip.dart';

class MediaSummaryCard extends StatelessWidget {
  const MediaSummaryCard({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final entry = info.entries.first;
    final duration = info.totalDuration;
    final meta = <Widget>[
      if (info.uploader != null) _Meta(icon: Icons.person_outline_rounded, text: info.uploader!),
      if (info.isPlaylist)
        _Meta(icon: Icons.video_library_outlined, text: Fmt.plural(info.totalCount, 'video')),
      if (duration != null)
        _Meta(
          icon: Icons.schedule_rounded,
          text: info.isPlaylist && info.entriesWithoutDuration > 0
              ? '${Fmt.durationLong(duration)}+'
              : (info.isPlaylist ? Fmt.durationLong(duration) : Fmt.duration(duration)),
        ),
      _Meta(icon: Icons.public_rounded, text: _sourceLabel(info)),
      if (!info.isPlaylist && entry.maxResolution != null)
        _Meta(icon: Icons.high_quality_outlined, text: 'Up to ${entry.maxResolution}p'),
    ];

    return AppCard(
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final thumb = MediaThumbnail(
          url: info.thumbnailUrl,
          width: narrow ? constraints.maxWidth : 208,
          height: narrow ? constraints.maxWidth * 9 / 16 : 117,
          radius: Gap.radiusMd,
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(
                  label: info.isPlaylist ? 'Playlist' : 'Video',
                  tone: ChipTone.accent,
                  icon: info.isPlaylist ? Icons.playlist_play_rounded : Icons.play_arrow_rounded,
                ),
                if (info.unavailableCount > 0) ...[
                  const SizedBox(width: Gap.sm),
                  StatusChip(
                    label: '${info.unavailableCount} unavailable',
                    tone: ChipTone.warning,
                    icon: Icons.block_rounded,
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(info.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleLarge),
            const SizedBox(height: Gap.sm),
            Wrap(spacing: Gap.lg, runSpacing: Gap.xs, children: meta),
            if (!info.isPlaylist && entry.hasFormatInfo) ...[
              const SizedBox(height: Gap.md),
              _QualityStrip(qualities: entry.availableQualities),
            ],
            if (info.reportedCount != null && info.reportedCount! > info.totalCount) ...[
              const SizedBox(height: Gap.sm),
              Text(
                'The source reports ${info.reportedCount} items; ${info.reportedCount! - info.totalCount} are hidden or unavailable to you.',
                style: context.text.bodySmall?.copyWith(color: c.warning),
              ),
            ],
          ],
        );
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [thumb, const SizedBox(height: Gap.lg), details]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [thumb, const SizedBox(width: Gap.lg), Expanded(child: details)],
        );
      }),
    );
  }
}

/// Human-friendly source, e.g. "youtube.com" rather than "YoutubeTab".
String _sourceLabel(MediaInfo info) {
  final host = Uri.tryParse(info.sourceUrl)?.host ?? '';
  if (host.isNotEmpty) return host.replaceFirst(RegExp(r'^(www|m)\.'), '');
  return info.extractor.replaceAll(RegExp(r'(Tab|Playlist)$'), '');
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.palette.textTertiary),
        const SizedBox(width: 5),
        Text(text, style: context.text.bodySmall),
      ],
    );
  }
}

class _QualityStrip extends StatelessWidget {
  const _QualityStrip({required this.qualities});
  final Set<VideoQuality> qualities;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Available:', style: context.text.labelMedium),
        for (final q in VideoQuality.values.where((q) => q.height != null))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: qualities.contains(q) ? c.borderStrong : c.border),
            ),
            child: Text(
              '${q.height}p',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: qualities.contains(q) ? c.textPrimary : c.textTertiary,
                decoration: qualities.contains(q) ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
      ],
    );
  }
}
