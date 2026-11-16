import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/presentation/about_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../theme/app_palette.dart';
import 'routes.dart';

/// Cross-fade with a slight upward drift. Pages are transparent over the
/// shared backdrop, so the outgoing page fades out (secondary animation)
/// instead of vanishing at the end of the transition.
Page<void> _page(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: Motion.slow,
  reverseTransitionDuration: Motion.medium,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final enter = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.6, curve: Motion.exit),
    );
    return FadeTransition(
      opacity: ReverseAnimation(leave),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(enter),
          child: child,
        ),
      ),
    );
  },
);

GoRouter buildRouter({String initialLocation = Routes.home}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', redirect: (_, _) => Routes.home),
    GoRoute(path: '/dashboard', redirect: (_, _) => Routes.home),
    GoRoute(path: Routes.queue, redirect: (_, _) => '${Routes.downloads}?tab=queued'),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: Routes.home, pageBuilder: (_, s) => _page(s, const DashboardScreen())),
        GoRoute(
          path: Routes.downloads,
          pageBuilder: (_, s) => _page(s, DownloadsScreen(initialTab: s.uri.queryParameters['tab'])),
        ),
        GoRoute(path: Routes.history, pageBuilder: (_, s) => _page(s, const HistoryScreen())),
        GoRoute(path: Routes.settings, pageBuilder: (_, s) => _page(s, const SettingsScreen())),
        GoRoute(path: Routes.about, pageBuilder: (_, s) => _page(s, const AboutScreen())),
      ],
    ),
  ],
);
