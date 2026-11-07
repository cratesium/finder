import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'log_sanitizer.dart';

/// Log levels selectable in Settings.
enum LogLevelSetting {
  error('Errors only', Level.SEVERE),
  warning('Warnings', Level.WARNING),
  info('Info', Level.INFO),
  debug('Debug (verbose)', Level.FINE);

  const LogLevelSetting(this.label, this.level);
  final String label;
  final Level level;
}

/// Structured, rotating, sanitized file logging.
///
/// Each record is written as a single line:
/// `2026-11-05T10:12:00.000Z INFO  [downloader] message {key: value}`.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const _maxBytes = 2 * 1024 * 1024;
  static const _keepFiles = 4;

  IOSink? _sink;
  StreamSubscription<LogRecord>? _sub;
  String? _logDirectory;

  String? get logDirectory => _logDirectory;
  String? get currentLogFile =>
      _logDirectory == null ? null : p.join(_logDirectory!, 'coursegrab.log');

  /// Initializes the root logger. Safe to call more than once.
  Future<void> init({
    required String directory,
    LogLevelSetting level = LogLevelSetting.info,
    bool echoToConsole = false,
  }) async {
    await close();
    _logDirectory = directory;
    hierarchicalLoggingEnabled = false;
    Logger.root.level = level.level;
    try {
      await Directory(directory).create(recursive: true);
      await _rotateIfNeeded(directory);
      _sink = File(currentLogFile!).openWrite(mode: FileMode.append);
    } catch (e) {
      // Logging must never crash the app; fall back to console only.
      stderr.writeln('CourseGrab: unable to open log file: $e');
    }
    _sub = Logger.root.onRecord.listen((record) {
      final line = format(record);
      _sink?.writeln(line);
      if (echoToConsole) {
        // ignore: avoid_print
        print(line);
      }
    });
  }

  void setLevel(LogLevelSetting level) => Logger.root.level = level.level;

  Future<void> flush() async => _sink?.flush();

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  static String format(LogRecord r) {
    final buf = StringBuffer()
      ..write(r.time.toUtc().toIso8601String())
      ..write(' ')
      ..write(r.level.name.padRight(7))
      ..write(' [')
      ..write(r.loggerName.isEmpty ? 'app' : r.loggerName)
      ..write('] ')
      ..write(LogSanitizer.sanitize(r.message));
    if (r.error != null) {
      buf.write(' | error: ${LogSanitizer.sanitize(r.error.toString())}');
    }
    if (r.stackTrace != null) {
      buf.write('\n${LogSanitizer.sanitize(r.stackTrace.toString())}');
    }
    return buf.toString();
  }

  static Future<void> _rotateIfNeeded(String directory) async {
    final current = File(p.join(directory, 'coursegrab.log'));
    if (!await current.exists() || await current.length() < _maxBytes) return;
    for (var i = _keepFiles - 1; i >= 1; i--) {
      final older = File(p.join(directory, 'coursegrab.$i.log'));
      if (await older.exists()) {
        if (i == _keepFiles - 1) {
          await older.delete();
        } else {
          await older.rename(p.join(directory, 'coursegrab.${i + 1}.log'));
        }
      }
    }
    await current.rename(p.join(directory, 'coursegrab.1.log'));
  }
}
