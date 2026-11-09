import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/page_scaffold.dart';
import '../../settings/application/dependency_controller.dart';
import '../application/dashboard_controller.dart';
import 'widgets/download_options_panel.dart';
import 'widgets/entry_list.dart';
import 'widgets/media_summary_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    return PageScaffold(
      title: 'Dashboard',
      subtitle: 'Paste a link to a video or playlist you own or are authorized to download.',
      scrollable: false,
      actions: [
        if (state.phase is! DetectIdle)
          OutlinedButton.icon(
            onPressed: () => ref.read(dashboardProvider.notifier).reset(),
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Start over'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UrlInputBar(),
          const SizedBox(height: Gap.lg),
          Expanded(
            child: switch (state.phase) {
              DetectIdle() => const _IdleView(),
              DetectLoading(:final url) => _LoadingView(url: url),
              DetectFailed(:final error) => Align(
                  alignment: Alignment.topCenter,
                  child: InlineBanner.error(
                    error,
                    action: TextButton(
                      onPressed: () => ref.read(dashboardProvider.notifier).detect(),
                      child: const Text('Try again'),
                    ),
                  ),
                ),
              DetectLoaded() => const _LoadedView(),
            },
          ),
        ],
      ),
    );
  }
}

/// URL field with paste and detect actions.
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
    ref.read(dashboardProvider.notifier).detect(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final state = ref.watch(dashboardProvider);
    final loading = state.phase is DetectLoading;
    ref.listen(dashboardProvider.select((s) => s.url), (_, next) {
      if (_controller.text != next) _controller.text = next;
    });

    return AppCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const Key('url-field'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              enabled: !loading,
              onChanged: (v) => ref.read(dashboardProvider.notifier).setUrl(v),
              onSubmitted: (_) => _detect(),
              style: context.text.bodyLarge,
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/playlist?list=…',
                prefixIcon: const Icon(Icons.link_rounded, size: 18),
                errorText: state.urlError,
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  onPressed: loading ? null : _paste,
                  icon: Icon(Icons.content_paste_rounded, size: 17, color: c.textSecondary),
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              key: const Key('detect-button'),
              onPressed: loading ? null : _detect,
              icon: const Icon(Icons.travel_explore_rounded, size: 17),
              label: const Text('Detect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deps = ref.watch(dependencyProvider).value;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (deps != null && !deps.ytDlp.isReady) ...[
            InlineBanner(
              tone: BannerTone.warning,
              title: 'yt-dlp is not set up',
              message: 'finder uses yt-dlp to read and download media. Install it with one click in Settings.',
              action: FilledButton(
                onPressed: () => context.go(Routes.settings),
                child: const Text('Open Settings'),
              ),
            ),
            const SizedBox(height: Gap.md),
          ] else if (deps != null && !deps.ffmpeg.isReady) ...[
            InlineBanner(
              tone: BannerTone.warning,
              title: 'FFmpeg is not set up',
              message: 'FFmpeg is needed to merge video and audio streams and to extract audio.',
              action: OutlinedButton(
                onPressed: () => context.go(Routes.settings),
                child: const Text('Set up'),
              ),
            ),
            const SizedBox(height: Gap.md),
          ],
          const AppCard(
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Start with a link',
              message:
                  'Paste a single video or a whole playlist. finder reads its details first — nothing is downloaded until you choose.',
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends ConsumerWidget {
  const _LoadingView({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = Uri.tryParse(url)?.host ?? 'the source';
    return Align(
      alignment: Alignment.topCenter,
      child: AppCard(
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reading metadata from $host…', style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text('Large playlists can take a minute. Nothing is downloaded yet.',
                      style: context.text.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: () => ref.read(dashboardProvider.notifier).cancelDetect(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(dashboardProvider.select((s) => s.info))!;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 920;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: MediaSummaryCard(info: info)),
                  const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
                  EntryListSliver(info: info),
                ],
              ),
            ),
            const SizedBox(width: Gap.lg),
            const SizedBox(
              width: 340,
              child: SingleChildScrollView(child: DownloadOptionsPanel()),
            ),
          ],
        );
      }
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: MediaSummaryCard(info: info)),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
          const SliverToBoxAdapter(child: DownloadOptionsPanel()),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.lg)),
          EntryListSliver(info: info),
        ],
      );
    });
  }
}
