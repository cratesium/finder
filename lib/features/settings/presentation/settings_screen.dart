import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/path_utils.dart';
import '../../../models/app_settings.dart';
import '../../../models/dependency_status.dart';
import '../../../models/download_options.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/page_scaffold.dart';
import '../application/settings_controller.dart';
import 'dependency_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);

    Future<void> update(AppSettings Function(AppSettings) f) async {
      final ok = await ctrl.change(f);
      if (!ok && context.mounted) showToast(context, 'Settings couldn\'t be saved. See the logs for details.');
    }

    Future<void> pickDir() async {
      final dir = await ref.read(directoryPickerProvider).pickDirectory(initialDirectory: s.downloadDirectory);
      if (dir == null) return;
      if (!await PathUtils.ensureWritableDirectory(dir)) {
        if (context.mounted) showToast(context, 'CourseGrab can\'t write to that folder.');
        return;
      }
      await update((x) => x.copyWith(downloadDirectory: dir));
    }

    return PageScaffold(
      title: 'Settings',
      subtitle: 'Preferences are saved automatically on this computer.',
      maxContentWidth: 980,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dependencies', style: context.text.titleMedium),
          const SizedBox(height: 2),
          Text('Detected automatically. Custom paths are validated before use.', style: context.text.bodySmall),
          const SizedBox(height: Gap.md),
          LayoutBuilder(builder: (context, constraints) {
            final cards = const [
              DependencyCard(kind: DependencyKind.ytDlp),
              DependencyCard(kind: DependencyKind.ffmpeg),
            ];
            if (constraints.maxWidth < 760) {
              return Column(children: [cards[0], const SizedBox(height: Gap.md), cards[1]]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: Gap.md),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          }),
          const SizedBox(height: Gap.xl),
          _Section(title: 'Downloads', children: [
            FieldRow(
              label: 'Default download folder',
              description: PathUtils.displayPath(s.downloadDirectory),
              child: OutlinedButton.icon(
                onPressed: pickDir,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Change…'),
              ),
            ),
            FieldRow(
              label: 'Default mode',
              child: AppDropdown<DownloadMode>(
                value: s.defaultMode,
                items: DownloadMode.values,
                labelOf: (m) => m.label,
                onChanged: (v) => update((x) => x.copyWith(defaultMode: v)),
              ),
            ),
            FieldRow(
              label: 'Default resolution',
              description: 'The best stream at or below this is used when available.',
              child: AppDropdown<VideoQuality>(
                value: s.defaultQuality,
                items: VideoQuality.values,
                labelOf: (q) => q.label,
                onChanged: (v) => update((x) => x.copyWith(defaultQuality: v)),
              ),
            ),
            FieldRow(
              label: 'Default container',
              child: AppDropdown<ContainerFormat>(
                value: s.defaultContainer,
                items: ContainerFormat.values,
                labelOf: (f) => f.label,
                onChanged: (v) => update((x) => x.copyWith(defaultContainer: v)),
              ),
            ),
            FieldRow(
              label: 'Default audio format',
              description: 'Used for audio-only downloads.',
              child: AppDropdown<AudioFormat>(
                value: s.defaultAudioFormat,
                items: AudioFormat.values,
                labelOf: (f) => f.label,
                onChanged: (v) => update((x) => x.copyWith(defaultAudioFormat: v)),
              ),
            ),
            FieldRow(
              label: 'Default MP3 quality',
              child: AppDropdown<AudioQuality>(
                value: s.defaultAudioQuality,
                items: AudioQuality.values,
                labelOf: (q) => q.label,
                onChanged: (v) => update((x) => x.copyWith(defaultAudioQuality: v)),
              ),
            ),
            FieldRow(
              label: 'Maximum concurrent downloads',
              child: SizedBox(
                width: 240,
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: s.maxConcurrentDownloads.toDouble(),
                        min: 1,
                        max: AppConfig.maxConcurrentLimit.toDouble(),
                        divisions: AppConfig.maxConcurrentLimit - 1,
                        label: '${s.maxConcurrentDownloads}',
                        onChanged: (v) => update((x) => x.copyWith(maxConcurrentDownloads: v.round())),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      child: Text('${s.maxConcurrentDownloads}', style: context.text.titleSmall),
                    ),
                  ],
                ),
              ),
            ),
            FieldRow(
              label: 'Number playlist items',
              description: 'Prefix files with their playlist position, e.g. "003 - Title".',
              child: Switch(
                value: s.numberPlaylistItems,
                onChanged: (v) => update((x) => x.copyWith(numberPlaylistItems: v)),
              ),
            ),
            FieldRow(
              label: 'Skip completed videos',
              description: 'Don\'t download items already saved to the same folder in the same format.',
              child: Switch(
                value: s.skipCompleted,
                onChanged: (v) => update((x) => x.copyWith(skipCompleted: v)),
              ),
            ),
          ]),
          const SizedBox(height: Gap.xl),
          _Section(title: 'Network', children: [
            FieldRow(
              label: 'Use system certificates',
              description: 'Let yt-dlp trust the certificates your operating system trusts. Required on '
                  'networks with TLS inspection (e.g. managed work computers). Verification stays on.',
              child: Switch(
                value: s.useSystemCertificates,
                onChanged: (v) => update((x) => x.copyWith(useSystemCertificates: v)),
              ),
            ),
          ]),
          const SizedBox(height: Gap.xl),
          _Section(title: 'Appearance & notifications', children: [
            FieldRow(
              label: 'Theme',
              child: AppDropdown<ThemePreference>(
                value: s.theme,
                items: ThemePreference.values,
                labelOf: (t) => t.label,
                onChanged: (v) => update((x) => x.copyWith(theme: v)),
              ),
            ),
            FieldRow(
              label: 'Download notifications',
              description: 'Show a system notification when a download completes or fails.',
              child: Switch(
                value: s.notificationsEnabled,
                onChanged: (v) => update((x) => x.copyWith(notificationsEnabled: v)),
              ),
            ),
          ]),
          const SizedBox(height: Gap.xl),
          _Section(title: 'Diagnostics', children: [
            FieldRow(
              label: 'Logging level',
              description: 'Logs stay on this computer. Home-folder paths and credentials in URLs are redacted.',
              child: AppDropdown<LogLevelSetting>(
                value: s.logLevel,
                items: LogLevelSetting.values,
                labelOf: (l) => l.label,
                onChanged: (v) => update((x) => x.copyWith(logLevel: v)),
              ),
            ),
            FieldRow(
              label: 'Log files',
              description: PathUtils.displayPath(ref.read(appPathsProvider).logDir),
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await AppLogger.instance.flush();
                    await ref.read(fileOpenerProvider).openFolder(ref.read(appPathsProvider).logDir);
                  } catch (e) {
                    if (context.mounted) showErrorToast(context, e);
                  }
                },
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Open logs folder'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.text.titleMedium),
        const SizedBox(height: Gap.md),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) Divider(height: 1, color: c.border.withValues(alpha: 0.7)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
