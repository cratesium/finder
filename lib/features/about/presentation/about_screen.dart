import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/page_scaffold.dart';
import '../../settings/application/dependency_controller.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final platform = ref.watch(platformInfoProvider);
    final deps = ref.watch(dependencyProvider).value;

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 140, child: Text(k, style: context.text.bodySmall)),
              Expanded(child: Text(v, style: context.text.bodyMedium)),
            ],
          ),
        );

    return PageScaffold(
      title: 'About',
      maxContentWidth: 900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.south_rounded, color: c.onAccent, size: 30),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConfig.appName, style: context.text.headlineSmall),
                      Text('Version ${AppConfig.version} (${AppConfig.buildNumber})', style: context.text.bodySmall),
                      const SizedBox(height: Gap.xs),
                      Text('A local desktop download manager for media you own or are authorized to access.',
                          style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('System'),
                row('Platform', platform.label),
                row('yt-dlp', deps?.ytDlp.version ?? 'not found'),
                row('FFmpeg', deps?.ffmpeg.version ?? 'not found'),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Responsible use'),
                Text(
                  'Only download content you own, have created, or have explicit permission to download. '
                  'CourseGrab does not bypass DRM, paywalls, sign-in requirements or other access restrictions, '
                  'and respects the terms of the platforms you use. Everything runs locally: no media, history '
                  'or usage data is uploaded anywhere.',
                  style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Third-party software'),
                row('yt-dlp', 'The Unlicense · github.com/yt-dlp/yt-dlp'),
                row('FFmpeg', 'LGPL 2.1+ / GPL (depends on build) · ffmpeg.org'),
                row('Flutter', 'BSD 3-Clause · flutter.dev'),
                row('SQLite', 'Public domain · sqlite.org'),
                row('Dart packages', 'Riverpod, go_router, sqflite_common_ffi, file_selector, path_provider, logging, crypto, intl, flutter_local_notifications — see their licenses.'),
                const SizedBox(height: Gap.sm),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppConfig.appName,
                    applicationVersion: AppConfig.version,
                  ),
                  child: const Text('View all open-source licenses'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
