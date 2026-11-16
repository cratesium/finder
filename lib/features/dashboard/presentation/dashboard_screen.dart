import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/backdrop.dart';
import '../../../widgets/brand.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/reveal.dart';
import '../../downloads/application/download_providers.dart';
import '../../settings/application/dependency_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../application/dashboard_controller.dart';
import 'widgets/download_options_panel.dart';
import 'widgets/entry_list.dart';
import 'widgets/library_card.dart';
import 'widgets/media_summary_card.dart';
import 'widgets/recent_downloads.dart';

/// Home: paste a link, preview it, choose quality, download.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(dashboardProvider.select((s) => s.phase));
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final wide = constraints.maxWidth >= 1000;
        final gutter = narrow ? Gap.lg : Gap.xxl;

        final top = <Widget>[
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: Motion.medium,
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: phase is DetectIdle
                  ? const Column(
                      key: ValueKey('hero'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HomeHero(),
                        SizedBox(height: Gap.xl),
                      ],
                    )
                  : const Column(
                      key: ValueKey('compact'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hero(compact: true),
                        SizedBox(height: Gap.lg),
                      ],
                    ),
            ),
          ),
          const UrlInputBar(),
          const SizedBox(height: Gap.lg),
        ];

        Widget body;
        if (phase is DetectLoaded && wide) {
          // Two columns: preview + entries on the left, options on the right.
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...top,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Reveal(
                              key: ObjectKey(phase.info),
                              child: MediaSummaryCard(info: phase.info),
                            ),
                          ),
                          if (phase.info.isPlaylist) ...[
                            const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
                            EntryListSliver(info: phase.info),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.lg),
                    SizedBox(
                      width: 350,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: Gap.xl),
                        child: Reveal(
                          key: ObjectKey(phase.info),
                          delay: const Duration(milliseconds: 70),
                          child: const DownloadOptionsPanel(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else {
          body = CustomScrollView(
            slivers: [
              SliverList.list(children: top),
              ...switch (phase) {
                DetectIdle() => [
                  const SliverToBoxAdapter(
                    child: Reveal(key: ValueKey('idle'), child: _IdleView()),
                  ),
                ],
                DetectLoading(:final url) => [
                  SliverToBoxAdapter(
                    child: Reveal(
                      key: ValueKey('loading:$url'),
                      child: _LoadingView(url: url),
                    ),
                  ),
                ],
                DetectFailed(:final error) => [
                  SliverToBoxAdapter(
                    child: Reveal(
                      key: ObjectKey(error),
                      child: InlineBanner.error(
                        error,
                        action: TextButton(
                          onPressed: () => ref.read(dashboardProvider.notifier).detect(),
                          child: const Text('Try again'),
                        ),
                      ),
                    ),
                  ),
                ],
                DetectLoaded(:final info) => [
                  SliverToBoxAdapter(
                    child: Reveal(
                      key: ObjectKey(info),
                      child: MediaSummaryCard(info: info),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
                  SliverToBoxAdapter(
                    child: Reveal(
                      key: ObjectKey(info),
                      delay: const Duration(milliseconds: 70),
                      child: const DownloadOptionsPanel(),
                    ),
                  ),
                  if (info.isPlaylist) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
                    EntryListSliver(info: info),
                  ],
                ],
              },
              const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
            ],
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(padding: EdgeInsets.fromLTRB(gutter, narrow ? Gap.lg : Gap.xl, gutter, 0), child: body),
          ),
        );
      },
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final hasResult = ref.watch(dashboardProvider.select((s) => s.phase is! DetectIdle));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AnimatedSize(
            duration: Motion.medium,
            curve: Motion.curve,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? 'Home' : 'Download videos & playlists',
                  style: compact ? context.text.headlineSmall : context.text.headlineMedium,
                ),
                if (!compact) ...[
                  const SizedBox(height: Gap.sm),
                  Text(
                    'Paste a link, pick a quality, and Finder takes care of the rest. '
                    'Only download content you own or are authorized to save.',
                    style: context.text.bodyLarge?.copyWith(color: c.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasResult)
          OutlinedButton.icon(
            onPressed: () => ref.read(dashboardProvider.notifier).clearResult(),
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('New link'),
          ),
      ],
    );
  }
}

/// Idle Home header on the backdrop: glass brand pill, the total downloaded
/// as a big figure, and round quick actions.
class _HomeHero extends ConsumerWidget {
  const _HomeHero();

  static (String, String) _split(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final fixed = v.toStringAsFixed(i < 2 ? 0 : 2);
    final dot = fixed.indexOf('.');
    return dot < 0 ? (fixed, ' ${units[i]}') : (fixed.substring(0, dot), '${fixed.substring(dot)} ${units[i]}');
  }

  Future<void> _paste(BuildContext context, WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!context.mounted) return;
    if (text == null || text.isEmpty) {
      showToast(context, 'The clipboard doesn\'t contain any text.');
      return;
    }
    ref.read(dashboardProvider.notifier).setUrl(text);
    await ref.read(dashboardProvider.notifier).detect(text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final library = ref.watch(completedLibraryProvider).value ?? const [];
    final bytes = library.fold<int>(0, (a, r) => a + (r.fileSize ?? 0));
    final active = ref.watch(activeTaskCountProvider) + ref.watch(queuedTaskCountProvider);
    final isDesktop = ref.watch(platformInfoProvider).isDesktop;
    final (whole, rest) = _split(bytes);
    final big = context.text.displayMedium?.copyWith(color: c.textPrimary, fontWeight: FontWeight.w300);

    Future<void> openFolder() async {
      try {
        await ref.read(fileOpenerProvider).openFolder(ref.read(settingsProvider).downloadDirectory);
      } catch (e) {
        if (context.mounted) showErrorToast(context, e);
      }
    }

    final actions = [
      _RoundAction(icon: Icons.north_east_rounded, label: 'Paste', onTap: () => _paste(context, ref)),
      _RoundAction(icon: Icons.south_west_rounded, label: 'Active', onTap: () => context.go(Routes.downloads)),
      _RoundAction(icon: Icons.swap_horiz_rounded, label: 'History', onTap: () => context.go(Routes.history)),
      isDesktop
          ? _RoundAction(icon: Icons.add_rounded, label: 'Folder', onTap: openFolder)
          : _RoundAction(icon: Icons.add_rounded, label: 'Settings', onTap: () => context.go(Routes.settings)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Glass header: activity bell joined to the brand pill.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: active > 0 ? '$active active or queued' : 'Downloads',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go(Routes.downloads),
                child: GlassSurface(
                  width: 52,
                  height: 52,
                  child: Badge(
                    isLabelVisible: active > 0,
                    smallSize: 8,
                    backgroundColor: const Color(0xFFFF5A6E),
                    alignment: const AlignmentDirectional(0.45, -0.55),
                    child: Center(child: Icon(Icons.notifications_none_rounded, size: 24, color: c.textPrimary)),
                  ),
                ),
              ),
            ),
            Container(width: 10, height: 18, color: c.surfaceRaised),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => context.go(Routes.about),
              child: GlassSurface(
                height: 52,
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 36),
                    const SizedBox(width: Gap.md),
                    BrandWordmark(fontSize: 18),
                    const SizedBox(width: Gap.xs),
                    Icon(Icons.keyboard_arrow_down_rounded, color: c.textPrimary, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xl),
        Semantics(
          label: 'Downloaded ${Fmt.bytes(bytes)}',
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: whole, style: big),
                  TextSpan(
                    text: rest,
                    style: big?.copyWith(fontSize: (big.fontSize ?? 52) * 0.55, letterSpacing: -0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          'Downloaded · ${Fmt.plural(library.length, 'file')}',
          style: context.text.titleLarge?.copyWith(color: c.textSecondary, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: Gap.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = math.min(96.0, (constraints.maxWidth - Gap.md * 3) / 4);
            return Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [for (final a in actions) SizedBox(width: w, child: a)],
            );
          },
        ),
      ],
    );
  }
}

/// Round frosted-glass quick action with a label underneath.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: GlassSurface(
                height: 62,
                width: double.infinity,
                child: Center(child: Icon(icon, size: 24, color: c.textPrimary)),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(label, style: context.text.bodyLarge?.copyWith(fontSize: 15, color: c.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// Mode selector, URL field with paste, and the Analyze action.
class UrlInputBar extends ConsumerStatefulWidget {
  const UrlInputBar({super.key});

  @override
  ConsumerState<UrlInputBar> createState() => _UrlInputBarState();
}

class _UrlInputBarState extends ConsumerState<UrlInputBar> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(dashboardProvider).url);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      showToast(context, 'The clipboard doesn\'t contain any text.');
      return;
    }
    _controller.text = text;
    ref.read(dashboardProvider.notifier).setUrl(text);
    await ref.read(dashboardProvider.notifier).detect(text);
  }

  void _detect() {
    FocusScope.of(context).unfocus();
    ref.read(dashboardProvider.notifier).detect(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final loading = state.phase is DetectLoading;
    ref.listen(dashboardProvider.select((s) => s.url), (_, next) {
      if (_controller.text != next) _controller.text = next;
    });
    return CardScope(
      builder: (context) {
        final c = context.palette;

        final field = TextField(
          key: const Key('url-field'),
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          enabled: !loading,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onChanged: (v) => ref.read(dashboardProvider.notifier).setUrl(v),
          onSubmitted: (_) => _detect(),
          style: context.text.bodyLarge,
          decoration: InputDecoration(
            hintText: state.mode == HomeMode.playlist ? 'Paste a playlist link…' : 'Paste a video link…',
            prefixIcon: Icon(Icons.link_rounded, size: 18, color: c.accent),
            errorText: state.urlError,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            suffixIcon: IconButton(
              tooltip: 'Paste from clipboard',
              onPressed: loading ? null : _paste,
              icon: Icon(Icons.content_paste_rounded, size: 17, color: c.textSecondary),
            ),
          ),
        );
        final analyze = KeyedSubtree(
          key: const Key('detect-button'),
          child: GradientButton(
            label: loading ? 'Analyzing…' : 'Analyze',
            icon: Icons.auto_awesome_rounded,
            loading: loading,
            height: 48,
            onPressed: loading ? null : _detect,
          ),
        );

        return AppCard(
          elevated: true,
          padding: const EdgeInsets.all(Gap.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: PillSelector<HomeMode>(
                          value: state.mode,
                          items: HomeMode.values,
                          labelOf: (m) => m.label,
                          iconOf: (m) => m.icon,
                          keyOf: (m) => Key('mode-${m.name}'),
                          onChanged: loading ? null : ref.read(dashboardProvider.notifier).setMode,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      if (!stacked && !state.modeChosenByUser && state.url.trim().isNotEmpty)
                        Text('Detected automatically', style: context.text.labelMedium)
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  if (stacked) ...[
                    field,
                    const SizedBox(height: Gap.sm),
                    analyze,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: Gap.sm),
                        analyze,
                      ],
                    ),
                  AnimatedSize(
                    duration: Motion.medium,
                    curve: Motion.curve,
                    child: state.isAmbiguousLink
                        ? Padding(
                            padding: const EdgeInsets.only(top: Gap.sm),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 14, color: c.info),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    state.mode == HomeMode.playlist
                                        ? 'This link points to a video inside a playlist. The whole playlist will be read — switch to Single video for just this one.'
                                        : 'This link points to a video inside a playlist. Only this video will be read — switch to Playlist for all of them.',
                                    style: context.text.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deps = ref.watch(dependencyProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deps != null && !deps.ytDlp.isReady) ...[
          InlineBanner(
            tone: BannerTone.warning,
            title: 'The download engine isn\'t available',
            message: 'Finder ships its own engine, but it couldn\'t be started. Open Settings for details.',
            action: TextButton(onPressed: () => context.go(Routes.settings), child: const Text('Open Settings')),
          ),
          const SizedBox(height: Gap.lg),
        ] else if (deps != null && !deps.ffmpeg.isReady) ...[
          InlineBanner(
            tone: BannerTone.warning,
            title: 'Media tools aren\'t available',
            message: 'They\'re needed to merge video and audio streams and to extract audio.',
            action: TextButton(onPressed: () => context.go(Routes.settings), child: const Text('Details')),
          ),
          const SizedBox(height: Gap.lg),
        ],
        const LibraryCard(),
        const SizedBox(height: Gap.lg),
        const RecentDownloadsSection(),
      ],
    );
  }
}

class _LoadingView extends ConsumerWidget {
  const _LoadingView({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardScope(
      builder: (context) {
        final c = context.palette;
        final host = (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp(r'^(www|m)\.'), '');
        final playlist = ref.watch(dashboardProvider.select((s) => s.mode == HomeMode.playlist));
        return AppCard(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              const _PulsingSkeleton(),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading ${playlist ? 'playlist' : 'video'} details${host.isEmpty ? '' : ' from $host'}…',
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      playlist
                          ? 'Large playlists can take a minute. Nothing is downloaded yet.'
                          : 'Fetching title, thumbnail and available qualities.',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Gap.md),
                    const BrandProgressBar(value: null, height: 4),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              TextButton(
                onPressed: () => ref.read(dashboardProvider.notifier).cancelDetect(),
                style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Thumbnail-shaped placeholder with a gentle pulse.
class _PulsingSkeleton extends StatefulWidget {
  const _PulsingSkeleton();

  @override
  State<_PulsingSkeleton> createState() => _PulsingSkeletonState();
}

class _PulsingSkeletonState extends State<_PulsingSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 112,
        height: 63,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Gap.radiusMd),
          gradient: LinearGradient(colors: [p.brandStart.withValues(alpha: 0.25), p.brandEnd.withValues(alpha: 0.18)]),
        ),
        child: Icon(Icons.movie_outlined, color: p.accent.withValues(alpha: 0.7)),
      ),
    );
  }
}
