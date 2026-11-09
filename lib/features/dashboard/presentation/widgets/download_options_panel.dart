import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/path_utils.dart';
import '../../../../models/download_options.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/common.dart';
import '../../../../widgets/feedback.dart';
import '../../../settings/application/dependency_controller.dart';
import '../../application/dashboard_controller.dart';

class DownloadOptionsPanel extends ConsumerWidget {
  const DownloadOptionsPanel({super.key});

  Future<void> _pickFolder(BuildContext context, WidgetRef ref, DownloadOptions o) async {
    final dir = await ref.read(directoryPickerProvider).pickDirectory(initialDirectory: o.destinationDir);
    if (dir == null) return;
    if (!await PathUtils.ensureWritableDirectory(dir)) {
      if (context.mounted) showToast(context, 'finder can\'t write to that folder. Choose another one.');
      return;
    }
    ref.read(dashboardProvider.notifier).setOptions(o.copyWith(destinationDir: dir));
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(dashboardProvider.notifier).enqueueSelected();
    if (!context.mounted) return;
    showToast(
      context,
      result.describe(),
      action: result.added > 0
          ? SnackBarAction(label: 'View', onPressed: () => context.go(Routes.downloads))
          : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final state = ref.watch(dashboardProvider);
    final info = state.info!;
    final o = state.options;
    final deps = ref.watch(dependencyProvider).value;
    final ffmpegReady = deps?.ffmpeg.isReady ?? false;
    final ytDlpReady = deps?.ytDlp.isReady ?? false;
    final available = state.availableQualities;
    final count = state.selectedEntries.length;
    void set(DownloadOptions next) => ref.read(dashboardProvider.notifier).setOptions(next);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Download options', style: context.text.titleMedium),
          const SizedBox(height: Gap.lg),
          const SectionLabel('Download as'),
          SegmentedButton<DownloadMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: DownloadMode.video, label: Text('Video'), icon: Icon(Icons.movie_outlined, size: 16)),
              ButtonSegment(value: DownloadMode.audioOnly, label: Text('Audio only'), icon: Icon(Icons.graphic_eq_rounded, size: 16)),
            ],
            selected: {o.mode},
            onSelectionChanged: (s) => set(o.copyWith(mode: s.first)),
          ),
          const SizedBox(height: Gap.lg),
          if (!o.isAudioOnly) ...[
            const SectionLabel('Quality'),
            AppDropdown<VideoQuality>(
              key: const Key('quality-dropdown'),
              width: double.infinity,
              value: available.contains(o.quality) ? o.quality : VideoQuality.best,
              items: VideoQuality.values,
              labelOf: (q) => q.label,
              isEnabled: available.contains,
              onChanged: (q) => set(o.copyWith(quality: q)),
            ),
            const SizedBox(height: 6),
            Text(
              info.isPlaylist
                  ? 'Each video uses the best stream at or below this quality. You\'ll be told if a video doesn\'t offer it.'
                  : 'Only resolutions this video actually offers can be selected.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Gap.lg),
            const SectionLabel('Container'),
            AppDropdown<ContainerFormat>(
              width: double.infinity,
              value: o.container,
              items: ContainerFormat.values,
              labelOf: (f) => f.label,
              onChanged: (f) => set(o.copyWith(container: f)),
            ),
            const SizedBox(height: 6),
            Text('Streams are merged without re-encoding, preserving source quality.',
                style: context.text.bodySmall),
          ] else ...[
            const SectionLabel('Audio format'),
            AppDropdown<AudioFormat>(
              width: double.infinity,
              value: o.audioFormat,
              items: AudioFormat.values,
              labelOf: (f) => f.label,
              onChanged: (f) => set(o.copyWith(audioFormat: f)),
            ),
            if (o.audioFormat == AudioFormat.mp3) ...[
              const SizedBox(height: Gap.md),
              const SectionLabel('MP3 quality'),
              AppDropdown<AudioQuality>(
                width: double.infinity,
                value: o.audioQuality,
                items: AudioQuality.values,
                labelOf: (q) => q.label,
                onChanged: (q) => set(o.copyWith(audioQuality: q)),
              ),
              const SizedBox(height: 6),
              Text('MP3 requires re-encoding, which can\'t exceed the source quality.',
                  style: context.text.bodySmall),
            ],
          ],
          const SizedBox(height: Gap.lg),
          const SectionLabel('Save to'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(Gap.radiusSm + 2),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: c.textTertiary),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Tooltip(
                    message: PathUtils.displayPath(o.destinationDir),
                    child: Text(PathUtils.displayPath(o.destinationDir),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ),
                ),
                TextButton(onPressed: () => _pickFolder(context, ref, o), child: const Text('Change')),
              ],
            ),
          ),
          if (info.isPlaylist) ...[
            const SizedBox(height: Gap.sm),
            Text('Saved in a sub-folder named after the playlist.', style: context.text.bodySmall),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(child: Text('Number files by playlist position', style: context.text.bodyMedium)),
                Switch(
                  value: o.numberPlaylistItems,
                  onChanged: (v) => set(o.copyWith(numberPlaylistItems: v)),
                ),
              ],
            ),
          ],
          if (deps != null && !ffmpegReady) ...[
            const SizedBox(height: Gap.lg),
            InlineBanner(
              tone: BannerTone.warning,
              message: o.isAudioOnly
                  ? 'FFmpeg is required to extract audio.'
                  : 'FFmpeg is required to merge video and audio.',
              action: TextButton(onPressed: () => context.go(Routes.settings), child: const Text('Fix')),
            ),
          ],
          const SizedBox(height: Gap.xl),
          FilledButton.icon(
            key: const Key('download-button'),
            onPressed: count == 0 || !ytDlpReady || state.enqueueing ? null : () => _download(context, ref),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(count == 0 ? 'Select videos to download' : 'Download ${Fmt.plural(count, 'video')}'),
          ),
        ],
      ),
    );
  }
}
