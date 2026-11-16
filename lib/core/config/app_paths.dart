import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Resolved per-user locations. Nothing here is hardcoded to a specific user.
class AppPaths {
  const AppPaths({
    required this.dataDir,
    required this.binDir,
    required this.logDir,
    required this.databasePath,
    required this.defaultDownloadDir,
  });

  final String dataDir;
  final String binDir;
  final String logDir;
  final String databasePath;
  final String defaultDownloadDir;

  /// [downloadFolder] overrides the default download folder (Android passes
  /// the public `Download/Finder` folder, since path_provider only exposes an
  /// app-private one there).
  static Future<AppPaths> resolve({String? downloadFolder}) async {
    final support = await getApplicationSupportDirectory();
    final data = support.path;
    await Directory(data).create(recursive: true);

    String downloads;
    try {
      // iOS: Documents is what the Files app shows under
      // "On My iPhone/iPad → Finder" (UIFileSharingEnabled).
      final d = Platform.isIOS ? await getApplicationDocumentsDirectory() : await getDownloadsDirectory();
      downloads = d?.path ?? _homeDownloads();
    } catch (_) {
      downloads = _homeDownloads();
    }
    final paths = AppPaths(
      dataDir: data,
      binDir: p.join(data, 'bin'),
      logDir: p.join(data, 'logs'),
      databasePath: p.join(data, AppConfig.databaseFileName),
      defaultDownloadDir: downloadFolder ?? p.join(downloads, AppConfig.appName),
    );
    await _migrateLegacyData(paths);
    return paths;
  }

  /// Carries history and settings over from the app's previous names
  /// (Cratesium 3.0, Finder 2.x, CourseGrab 1.x) the first time Finder starts.
  static Future<void> _migrateLegacyData(AppPaths paths) async {
    if (await File(paths.databasePath).exists()) return;
    final data = paths.dataDir;
    final parent = p.dirname(data);
    final grandParent = p.dirname(parent);
    final legacy = <String>[
      // Cratesium 3.0 used the same data folder with its own database name.
      p.join(data, 'cratesium.db'),
      // Windows (Cratesium 3.0): %APPDATA%\Cratesium\Cratesium
      p.join(grandParent, 'Cratesium', 'Cratesium', 'cratesium.db'),
      // macOS / iOS: ~/Library/Application Support/<bundle id>
      p.join(parent, 'com.finder.app', 'finder.db'),
      p.join(parent, 'com.coursegrab.coursegrab', 'coursegrab.db'),
      // Windows: %APPDATA%\<company>\<product>
      p.join(grandParent, 'Finder', 'Finder', 'finder.db'),
      p.join(grandParent, 'CourseGrab', 'CourseGrab', 'coursegrab.db'),
    ];
    for (final path in legacy) {
      final file = File(path);
      try {
        if (!await file.exists()) continue;
        await file.copy(paths.databasePath);
        Logger('paths').info('migrated history and settings from ${p.basename(path)}');
        return;
      } catch (e) {
        Logger('paths').warning('could not migrate legacy data', e);
      }
    }
  }

  static String _homeDownloads() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    return p.join(home, 'Downloads');
  }
}
