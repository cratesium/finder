import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/errors/app_error.dart';

final _log = Logger('storage');

/// Opens the local SQLite database and applies schema migrations.
///
/// Uses the FFI implementation, which runs SQLite on a background isolate so
/// queries never block the UI.
abstract final class StorageService {
  static const schemaVersion = 1;

  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    sqfliteFfiInit();
    _initialized = true;
  }

  static Future<Database> open(String path, {DatabaseFactory? factory}) async {
    ensureInitialized();
    final f = factory ?? databaseFactoryFfi;
    try {
      return await f.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async => _migrate(db, 0, version),
          onUpgrade: _migrate,
        ),
      );
    } on DatabaseException catch (e) {
      _log.severe('failed to open database', e);
      throw AppError.of(AppErrorKind.storage, detail: e.toString());
    }
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    _log.info('migrating database $from → $to');
    final batch = db.batch();
    if (from < 1) {
      batch.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dedupe_key TEXT NOT NULL UNIQUE,
          video_id TEXT NOT NULL,
          extractor TEXT NOT NULL,
          title TEXT NOT NULL,
          url TEXT NOT NULL,
          playlist_title TEXT,
          playlist_index INTEGER,
          thumbnail_url TEXT,
          created_at INTEGER NOT NULL,
          completed_at INTEGER,
          resolution TEXT,
          format TEXT,
          file_size INTEGER,
          file_path TEXT,
          destination_dir TEXT NOT NULL,
          status TEXT NOT NULL,
          error_message TEXT,
          options_json TEXT NOT NULL
        )''');
      batch.execute('CREATE INDEX idx_history_status ON history(status)');
      batch.execute('CREATE INDEX idx_history_created ON history(created_at)');
      batch.execute('CREATE INDEX idx_history_video ON history(extractor, video_id)');
    }
    await batch.commit(noResult: true);
  }
}
