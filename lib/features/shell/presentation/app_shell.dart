import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/backdrop.dart';
import '../../../widgets/brand.dart';
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
  _NavItem(Routes.home, 'Home', Icons.home_outlined, Icons.home_rounded),
  _NavItem(Routes.downloads, 'Downloads', Icons.downloading_outlined, Icons.downloading_rounded),
  _NavItem(Routes.history, 'History', Icons.history_outlined, Icons.history_rounded),
  _NavItem(Routes.settings, 'Settings', Icons.tune_outlined, Icons.tune_rounded),
  _NavItem(Routes.about, 'About', Icons.info_outline_rounded, Icons.info_rounded),
];

/// Sidebar + content layout shared by every screen. On phones (narrow
/// windows) the sidebar becomes a bottom navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return AuroraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  Expanded(child: SafeArea(bottom: false, child: child)),
                  _BottomNav(location: location),
                ],
              );
            }
            final compact = constraints.maxWidth < 960;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(location: location, compact: compact),
                VerticalDivider(width: 1, color: c.border.withValues(alpha: 0.5)),
                Expanded(child: SafeArea(left: false, child: child)),
              ],
            );
          },
        ),
      ),
    );
  }
}

int _badgeFor(String route, int active, int queued) => switch (route) {
  Routes.downloads => active + queued,
  _ => 0,
};

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
      duration: Motion.medium,
      curve: Motion.curve,
      width: compact ? 72 : 236,
      color: c.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 20, 26, 16, 28),
              child: Row(
                children: [
                  const BrandMark(size: 32),
                  if (!compact) ...[const SizedBox(width: Gap.md), const Expanded(child: BrandWordmark(fontSize: 17))],
                ],
              ),
            ),
            for (final item in _items)
              _NavTile(
                item: item,
                selected: location.startsWith(item.route),
                compact: compact,
                badge: _badgeFor(item.route, active, queued),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: deps.when(
                data: (s) => _EngineIndicator(
                  ok: s.allReady,
                  compact: compact,
                  label: s.allReady
                      ? 'Engine ready'
                      : !s.ytDlp.isReady
                      ? 'Download engine missing'
                      : 'Media tools missing',
                ),
                loading: () => _EngineIndicator(ok: null, compact: compact, label: 'Starting engine…'),
                error: (_, _) => _EngineIndicator(ok: false, compact: compact, label: 'Engine check failed'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final active = ref.watch(activeTaskCountProvider);
    final queued = ref.watch(queuedTaskCountProvider);
    final selected = _items.indexWhere((i) => location.startsWith(i.route));
    const p = AppPalette.card;
    Widget badged(_NavItem item, Widget icon) {
      final n = _badgeFor(item.route, active, queued);
      return Badge(isLabelVisible: n > 0, label: Text('$n'), backgroundColor: const Color(0xFFFF5A6E), child: icon);
    }

    // Floating white bar, like the cards; the selected item sits on an
    // iridescent orb.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Theme(
        data: AppTheme.card(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: NavigationBar(
              height: 68,
              backgroundColor: p.surface,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              selectedIndex: selected < 0 ? 0 : selected,
              onDestinationSelected: (i) => context.go(_items[i].route),
              destinations: [
                for (final item in _items)
                  NavigationDestination(
                    label: item.label,
                    tooltip: item.label,
                    icon: badged(item, Icon(item.icon, color: p.textPrimary, size: 24)),
                    selectedIcon: badged(
                      item,
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppPalette.orbGradient,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFB9A6FF).withValues(alpha: 0.55), blurRadius: 16),
                          ],
                        ),
                        child: Icon(item.activeIcon, color: p.textPrimary, size: 24),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
    final fg = selected || _hover ? c.textPrimary : c.textSecondary;
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go(widget.item.route),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? c.accentMuted : (_hover ? c.surfaceHover.withValues(alpha: 0.7) : Colors.transparent),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? c.borderStrong : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Badge(
                  isLabelVisible: widget.compact && widget.badge > 0,
                  backgroundColor: c.accent,
                  smallSize: 7,
                  child: selected
                      ? Icon(widget.item.activeIcon, size: 20, color: c.accent)
                      : Icon(widget.item.icon, size: 20, color: fg),
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: context.text.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.badge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${widget.badge}',
                        style: TextStyle(color: c.onAccent, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return widget.compact ? Tooltip(message: widget.item.label, child: tile) : tile;
  }
}

class _EngineIndicator extends StatelessWidget {
  const _EngineIndicator({required this.ok, required this.compact, required this.label});

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
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
      ),
    );
    return Tooltip(
      message: '$label — open Settings for details',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => context.go(Routes.settings),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              dot,
              if (!compact) ...[
                const SizedBox(width: Gap.sm + 2),
                Expanded(
                  child: Text(label, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
