import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../downloads/application/download_providers.dart';
import '../../settings/application/dependency_controller.dart';

class _NavItem {
  const _NavItem(this.route, this.label, this.icon, this.activeIcon);
  final String route;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _items = [
  _NavItem(Routes.dashboard, 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _NavItem(Routes.downloads, 'Downloads', Icons.download_outlined, Icons.download_rounded),
  _NavItem(Routes.queue, 'Queue', Icons.queue_outlined, Icons.queue_rounded),
  _NavItem(Routes.history, 'History', Icons.history_outlined, Icons.history_rounded),
  _NavItem(Routes.settings, 'Settings', Icons.settings_outlined, Icons.settings_rounded),
  _NavItem(Routes.about, 'About', Icons.info_outline_rounded, Icons.info_rounded),
];

/// Sidebar + content layout shared by every screen.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Scaffold(
      backgroundColor: c.background,
      body: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(location: location, compact: compact),
            VerticalDivider(width: 1, color: c.border),
            Expanded(child: child),
          ],
        );
      }),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location, required this.compact});

  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final active = ref.watch(activeTaskCountProvider);
    final queued = ref.watch(queuedTaskCountProvider);
    final deps = ref.watch(dependencyProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: compact ? 68 : 232,
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 20, 28, 16, 24),
            child: Row(
              children: [
                const _LogoMark(),
                if (!compact) ...[
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(AppConfig.appName,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(fontSize: 15.5, letterSpacing: -0.3)),
                  ),
                ],
              ],
            ),
          ),
          for (final item in _items)
            _NavTile(
              item: item,
              selected: location.startsWith(item.route),
              compact: compact,
              badge: switch (item.route) {
                Routes.downloads => active,
                Routes.queue => queued,
                _ => 0,
              },
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: deps.when(
              data: (s) => _DependencyIndicator(
                ok: s.allReady,
                compact: compact,
                label: s.allReady
                    ? 'Tools ready'
                    : !s.ytDlp.isReady
                        ? 'yt-dlp missing'
                        : 'FFmpeg missing',
              ),
              loading: () => _DependencyIndicator(ok: null, compact: compact, label: 'Checking tools…'),
              error: (_, _) => _DependencyIndicator(ok: false, compact: compact, label: 'Tool check failed'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Icon(Icons.south_rounded, size: 19, color: c.onAccent),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.item, required this.selected, required this.compact, required this.badge});

  final _NavItem item;
  final bool selected;
  final bool compact;
  final int badge;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final selected = widget.selected;
    final fg = selected ? c.textPrimary : (_hover ? c.textPrimary : c.textSecondary);
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(widget.item.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? c.surfaceRaised : (_hover ? c.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(Gap.radiusSm + 2),
            border: Border.all(color: selected ? c.border : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Badge(
                isLabelVisible: widget.compact && widget.badge > 0,
                backgroundColor: c.accent,
                smallSize: 7,
                child: Icon(selected ? widget.item.activeIcon : widget.item.icon,
                    size: 18, color: selected ? c.accent : fg),
              ),
              if (!widget.compact) ...[
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(widget.item.label,
                      style: context.text.bodyMedium?.copyWith(
                          color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                ),
                if (widget.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: c.accentMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${widget.badge}',
                        style: TextStyle(color: c.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.compact ? Tooltip(message: widget.item.label, child: tile) : tile;
  }
}

class _DependencyIndicator extends StatelessWidget {
  const _DependencyIndicator({required this.ok, required this.compact, required this.label});

  final bool? ok;
  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final color = ok == null ? c.textTertiary : (ok! ? c.success : c.warning);
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Tooltip(
      message: '$label — open Settings for details',
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: () => context.go(Routes.settings),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(Gap.radiusSm + 2),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              dot,
              if (!compact) ...[
                const SizedBox(width: Gap.sm + 2),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
