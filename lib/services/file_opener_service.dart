import 'dart:io';

import 'package:logging/logging.dart';

import '../core/errors/app_error.dart';
import 'android/android_toolchain.dart';

final _log = Logger('opener');

/// Opens files and folders with the operating system's default handlers.
///
/// Paths are passed as separate arguments to `open` / `explorer.exe`; no shell
/// is involved.
abstract interface class FileOpenerService {
  Future<void> openFile(String path);
  Future<void> revealInFolder(String path);
  Future<void> openFolder(String path);
}

class SystemFileOpener implements FileOpenerService {
  const SystemFileOpener();

  Future<void> _run(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, runInShell: false);
      // explorer.exe returns 1 even on success.
      if (r.exitCode != 0 && !Platform.isWindows) {
        _log.warning('$exe failed: ${r.stderr}');
        throw const AppError(AppErrorKind.unknown, 'The system couldn\'t open that item.');
      }
    } on ProcessException catch (e) {
      throw AppError(AppErrorKind.unknown, 'The system couldn\'t open that item.', detail: e.message);
    }
  }

  Future<void> _requireExists(String path, {bool directory = false}) async {
    final exists = directory ? await Directory(path).exists() : await File(path).exists();
    if (!exists) {
      throw AppError(
        AppErrorKind.unavailable,
        directory ? 'That folder no longer exists.' : 'That file no longer exists. It may have been moved or deleted.',
      );
    }
  }

  @override
  Future<void> openFile(String path) async {
    await _requireExists(path);
    if (Platform.isMacOS) return _run('/usr/bin/open', [path]);
    if (Platform.isWindows) return _run('explorer.exe', [path]);
    return _run('xdg-open', [path]);
  }

  @override
  Future<void> revealInFolder(String path) async {
    await _requireExists(path);
    if (Platform.isMacOS) return _run('/usr/bin/open', ['-R', path]);
    if (Platform.isWindows) return _run('explorer.exe', ['/select,', path]);
    return _run('xdg-open', [File(path).parent.path]);
  }

  @override
  Future<void> openFolder(String path) async {
    await _requireExists(path, directory: true);
    if (Platform.isMacOS) return _run('/usr/bin/open', [path]);
    if (Platform.isWindows) return _run('explorer.exe', [path]);
    return _run('xdg-open', [path]);
  }
}

/// Opens files with an Android `ACTION_VIEW` intent (via a FileProvider).
class AndroidFileOpener implements FileOpenerService {
  const AndroidFileOpener(this._toolchain);
  final AndroidToolchain _toolchain;

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      _log.warning('android open failed', e);
      throw AppError(AppErrorKind.unknown, 'No app on this device can open that item.', detail: '$e');
    }
  }

  @override
  Future<void> openFile(String path) async {
    if (!await File(path).exists()) {
      throw const AppError(AppErrorKind.unavailable, 'That file no longer exists. It may have been moved or deleted.');
    }
    await _guard(() => _toolchain.openFile(path));
  }

  // Android has no "reveal in folder"; opening the file is the closest match.
  @override
  Future<void> revealInFolder(String path) => openFile(path);

  @override
  Future<void> openFolder(String path) => _guard(() => _toolchain.openFolder(path));
}
