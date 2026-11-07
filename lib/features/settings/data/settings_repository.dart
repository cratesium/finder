import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/errors/app_error.dart';
import '../../../models/app_settings.dart';

final _log = Logger('settings');

abstract interface class SettingsRepository {
  Future<AppSettings> load({required String fallbackDirectory});
  Future<void> save(AppSettings settings);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  static const _key = 'app_settings';
  final Database _db;

  @override
  Future<AppSettings> load({required String fallbackDirectory}) async {
    try {
      final rows = await _db.query('settings', where: 'key = ?', whereArgs: [_key], limit: 1);
      if (rows.isEmpty) return AppSettings(downloadDirectory: fallbackDirectory);
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) return AppSettings(downloadDirectory: fallbackDirectory);
      return AppSettings.fromJson(decoded.cast<String, Object?>(),
          fallbackDirectory: fallbackDirectory);
    } on FormatException catch (e) {
      _log.warning('settings were corrupted; using defaults', e);
      return AppSettings(downloadDirectory: fallbackDirectory);
    } on DatabaseException catch (e) {
      _log.severe('failed to load settings', e);
      throw AppError.of(AppErrorKind.storage, detail: e.toString());
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await _db.insert(
        'settings',
        {'key': _key, 'value': jsonEncode(settings.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      _log.severe('failed to save settings', e);
      throw AppError.of(AppErrorKind.storage, detail: e.toString());
    }
  }
}
