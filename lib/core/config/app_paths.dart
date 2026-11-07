import 'dart:io';

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

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final data = support.path;
    await Directory(data).create(recursive: true);

    String downloads;
    try {
      final d = await getDownloadsDirectory();
      downloads = d?.path ?? _homeDownloads();
    } catch (_) {
      downloads = _homeDownloads();
    }
    return AppPaths(
      dataDir: data,
      binDir: p.join(data, 'bin'),
      logDir: p.join(data, 'logs'),
      databasePath: p.join(data, AppConfig.databaseFileName),
      defaultDownloadDir: p.join(downloads, AppConfig.appName),
    );
  }

  static String _homeDownloads() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    return p.join(home, 'Downloads');
  }
}
