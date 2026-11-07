import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_paths.dart';
import 'core/di/providers.dart';
import 'core/errors/app_error.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'features/history/data/history_repository.dart';
import 'features/settings/data/settings_repository.dart';
import 'services/storage_service.dart';

final _log = Logger('main');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppPaths paths;
  try {
    paths = await AppPaths.resolve();
  } catch (e) {
    runApp(StartupErrorApp(message: 'CourseGrab couldn\'t access its application data folder.\n\n$e'));
    return;
  }

  await AppLogger.instance.init(directory: paths.logDir);
  FlutterError.onError = (details) {
    _log.severe('Flutter error: ${details.exceptionAsString()}', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('Uncaught error', error, stack);
    return true;
  };
  _log.info('${AppConfig.appName} ${AppConfig.version} starting');

  try {
    final db = await StorageService.open(paths.databasePath);
    final settings = await SqliteSettingsRepository(db).load(fallbackDirectory: paths.defaultDownloadDir);
    AppLogger.instance.setLevel(settings.logLevel);
    final interrupted = await SqliteHistoryRepository(db).markInterrupted();
    if (interrupted > 0) _log.info('$interrupted download(s) were interrupted last session');

    runApp(ProviderScope(
      // Errors are surfaced to the user explicitly; don't silently retry.
      retry: (_, _) => null,
      overrides: [
        appPathsProvider.overrideWithValue(paths),
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
        interruptedAtStartupProvider.overrideWithValue(interrupted),
      ],
      child: const CourseGrabApp(),
    ));
  } on AppError catch (e) {
    _log.severe('startup failed', e);
    runApp(StartupErrorApp(message: '${e.message}\n\nDiagnostic logs: ${AppLogger.instance.logDirectory}'));
  }
}

/// Minimal app shown when startup fails (e.g. the database can't be opened).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CourseGrab couldn\'t start', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  SelectableText(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
