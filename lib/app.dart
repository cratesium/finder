import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'core/config/app_config.dart';
import 'core/di/providers.dart';
import 'core/logging/app_logger.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/downloads/application/download_providers.dart';
import 'features/settings/application/settings_controller.dart';
import 'models/app_settings.dart';

final _log = Logger('app');

class CourseGrabApp extends ConsumerStatefulWidget {
  const CourseGrabApp({super.key, this.router});

  /// Allows tests to inject a router with a custom initial location.
  final GoRouter? router;

  @override
  ConsumerState<CourseGrabApp> createState() => _CourseGrabAppState();
}

class _CourseGrabAppState extends ConsumerState<CourseGrabApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  late final AppLifecycleListener _lifecycle;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  /// Stops downloads and child processes before the app quits so no orphan
  /// yt-dlp/ffmpeg processes are left behind.
  Future<AppExitResponse> _onExitRequested() async {
    if (_exiting) return AppExitResponse.exit;
    _exiting = true;
    _log.info('exit requested; shutting down');
    try {
      await ref.read(downloadManagerProvider).shutdown().timeout(const Duration(seconds: 8));
    } catch (e) {
      _log.warning('download manager shutdown incomplete', e);
    }
    try {
      await ref.read(processServiceProvider).killAll().timeout(const Duration(seconds: 4));
    } catch (e) {
      _log.warning('process cleanup incomplete', e);
    }
    await AppLogger.instance.flush();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (theme) {
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.system => ThemeMode.system,
      },
      routerConfig: _router,
    );
  }
}
