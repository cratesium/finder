import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/brand.dart';
import '../../../widgets/page_scaffold.dart';
import '../../settings/application/dependency_controller.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformInfoProvider);
    final deps = ref.watch(dependencyProvider).value;

    String engineVersion(String? v) =>
        v == null || v.isEmpty ? 'not available' : (v.startsWith('builtin') ? 'built in' : v);

    return PageScaffold(
      title: 'About',
      maxContentWidth: 860,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardScope(
            builder: (context) {
              final c = context.palette;
              Widget row(String k, String v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 130, child: Text(k, style: context.text.bodySmall)),
                    Expanded(child: Text(v, style: context.text.bodyMedium)),
                  ],
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand block
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xxl),
                    child: Column(
                      children: [
                        const BrandMark(size: 76),
                        const SizedBox(height: Gap.lg),
                        Text(
                          AppConfig.appName,
                          style: context.text.headlineMedium?.copyWith(fontSize: 28, letterSpacing: -0.8),
                        ),
                        const SizedBox(height: Gap.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: c.accentMuted, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            'Version ${AppConfig.version} (${AppConfig.buildNumber})',
                            key: const Key('about-version'),
                            style: context.text.labelMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: Gap.lg),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Text(
                            'A self-contained video and playlist downloader. Everything it needs is built in — '
                            'install, open, paste a link.',
                            textAlign: TextAlign.center,
                            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
                          ),
                        ),
                        const SizedBox(height: Gap.xl),
                        SizedBox(width: 40, child: Divider(color: c.borderStrong)),
                        const SizedBox(height: Gap.lg),
                        // "Made by Cratesium" — quiet, elegant brand signature.
                        Row(
                          key: const Key('made-by'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'Made by ',
                              style: context.text.titleMedium?.copyWith(
                                color: c.textSecondary,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                            GradientText(
                              text: 'Cratesium',
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Application'),
                        row('Version', '${AppConfig.version} (build ${AppConfig.buildNumber})'),
                        row('Platform', platform.label),
                        row('Download engine', engineVersion(deps?.ytDlp.version)),
                        row('Media tools', engineVersion(deps?.ffmpeg.version)),
                        row('Privacy', 'Runs entirely on this device. No accounts, analytics or uploads.'),
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
                          'Finder does not bypass DRM, paywalls, sign-in requirements or other access restrictions, '
                          'and respects the terms of the platforms you use.',
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
                        row('Inter typeface', 'SIL Open Font License 1.1 · rsms.me/inter'),
                        row('Flutter', 'BSD 3-Clause · flutter.dev'),
                        row('SQLite', 'Public domain · sqlite.org'),
                        const SizedBox(height: Gap.sm),
                        TextButton(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: AppConfig.appName,
                            applicationVersion: AppConfig.version,
                            applicationIcon: const Padding(padding: EdgeInsets.all(Gap.md), child: BrandMark(size: 48)),
                            applicationLegalese: 'Made by Cratesium',
                          ),
                          child: const Text('View all open-source licenses'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: Gap.xl),
          Center(child: Text('© ${DateTime.now().year} Finder · Made by Cratesium', style: context.text.labelMedium)),
        ],
      ),
    );
  }
}
