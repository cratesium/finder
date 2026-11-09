import 'dart:io';

import 'package:path/path.dart' as p;

/// Path and filename helpers that are safe on both macOS and Windows.
abstract final class PathUtils {
  static final _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  static const _reservedWindowsNames = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Produces a single path segment that is valid on every supported OS.
  static String sanitizeSegment(String input, {int maxLength = 120}) {
    var s = input.replaceAll(_illegal, '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (s.length > maxLength) s = s.substring(0, maxLength).trim();
    if (s.isEmpty) s = 'Untitled';
    if (_reservedWindowsNames.contains(s.toUpperCase().split('.').first)) {
      s = '_$s';
    }
    return s;
  }

  /// Escapes a literal string so yt-dlp's output template engine keeps it as-is.
  static String escapeTemplate(String literal) => literal.replaceAll('%', '%%');

  /// Normalizes a directory for comparison/deduplication purposes.
  static String normalizeDir(String dir) {
    var n = p.normalize(p.absolute(dir));
    if (Platform.isWindows || Platform.isMacOS) n = n.toLowerCase();
    return n;
  }

  /// Returns true when [dir] exists (or can be created) and is writable.
  static Future<bool> ensureWritableDirectory(String dir) async {
    try {
      final d = Directory(dir);
      await d.create(recursive: true);
      final probe = File(p.join(dir, '.finder-write-test-${DateTime.now().microsecondsSinceEpoch}'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Shortens a path for display by replacing the home directory with `~`.
  static String displayPath(String path) {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home != null && home.length > 1 && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}
