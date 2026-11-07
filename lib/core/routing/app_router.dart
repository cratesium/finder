import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/presentation/about_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/queue/presentation/queue_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import 'routes.dart';

Page<void> _page(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

GoRouter buildRouter({String initialLocation = Routes.dashboard}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', redirect: (_, _) => Routes.dashboard),
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: Routes.dashboard, pageBuilder: (_, s) => _page(s, const DashboardScreen())),
            GoRoute(path: Routes.downloads, pageBuilder: (_, s) => _page(s, const DownloadsScreen())),
            GoRoute(path: Routes.queue, pageBuilder: (_, s) => _page(s, const QueueScreen())),
            GoRoute(path: Routes.history, pageBuilder: (_, s) => _page(s, const HistoryScreen())),
            GoRoute(path: Routes.settings, pageBuilder: (_, s) => _page(s, const SettingsScreen())),
            GoRoute(path: Routes.about, pageBuilder: (_, s) => _page(s, const AboutScreen())),
          ],
        ),
      ],
    );
