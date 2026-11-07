import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/errors/app_error.dart';
import '../../../models/download_options.dart';
import '../../../models/history_record.dart';

final _log = Logger('history');

abstract interface class HistoryRepository {
  /// Inserts or replaces the record with the same dedupe key. Returns its id.
  Future<int> upsert(HistoryRecord record);
  Future<HistoryRecord?> findByDedupeKey(String key);
  Future<List<HistoryRecord>> query(HistoryQuery query);
  Future<void> delete(int id);
  Future<void> clear();

  /// Marks records left `downloading` by a previous session as interrupted.
  Future<int> markInterrupted();
}

class SqliteHistoryRepository implements HistoryRepository {
  SqliteHistoryRepository(this._db);

  final Database _db;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on DatabaseException catch (e) {
      _log.severe('history $op failed', e);
      throw AppError.of(AppErrorKind.storage, detail: '$op: $e');
    }
  }

  static Map<String, Object?> toRow(HistoryRecord r) => {
        'dedupe_key': r.dedupeKey,
        'video_id': r.videoId,
        'extractor': r.extractor,
        'title': r.title,
        'url': r.url,
        'playlist_title': r.playlistTitle,
        'playlist_index': r.playlistIndex,
        'thumbnail_url': r.thumbnailUrl,
        'created_at': r.createdAt.millisecondsSinceEpoch,
        'completed_at': r.completedAt?.millisecondsSinceEpoch,
        'resolution': r.resolution,
        'format': r.format,
        'file_size': r.fileSize,
        'file_path': r.filePath,
        'destination_dir': r.destinationDir,
        'status': r.status.name,
        'error_message': r.errorMessage,
        'options_json': jsonEncode(r.options.toJson()),
      };

  static HistoryRecord fromRow(Map<String, Object?> row) {
    DownloadOptions options;
    try {
      options = DownloadOptions.fromJson(
          (jsonDecode(row['options_json'] as String) as Map).cast<String, Object?>());
    } catch (_) {
      options = DownloadOptions(destinationDir: row['destination_dir'] as String);
    }
    DateTime? ts(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return HistoryRecord(
      id: row['id'] as int?,
      dedupeKey: row['dedupe_key'] as String,
      videoId: row['video_id'] as String,
      extractor: row['extractor'] as String,
      title: row['title'] as String,
      url: row['url'] as String,
      playlistTitle: row['playlist_title'] as String?,
      playlistIndex: row['playlist_index'] as int?,
      thumbnailUrl: row['thumbnail_url'] as String?,
      createdAt: ts(row['created_at'])!,
      completedAt: ts(row['completed_at']),
      resolution: row['resolution'] as String?,
      format: row['format'] as String?,
      fileSize: row['file_size'] as int?,
      filePath: row['file_path'] as String?,
      destinationDir: row['destination_dir'] as String,
      status: HistoryStatus.fromName(row['status'] as String?),
      errorMessage: row['error_message'] as String?,
      options: options,
    );
  }

  @override
  Future<int> upsert(HistoryRecord record) => _guard('upsert', () async {
        final row = toRow(record);
        final existing = await _db.query('history',
            columns: ['id'], where: 'dedupe_key = ?', whereArgs: [record.dedupeKey], limit: 1);
        if (existing.isEmpty) {
          return _db.insert('history', row);
        }
        final id = existing.first['id'] as int;
        await _db.update('history', row, where: 'id = ?', whereArgs: [id]);
        return id;
      });

  @override
  Future<HistoryRecord?> findByDedupeKey(String key) => _guard('find', () async {
        final rows = await _db.query('history', where: 'dedupe_key = ?', whereArgs: [key], limit: 1);
        return rows.isEmpty ? null : fromRow(rows.first);
      });

  @override
  Future<List<HistoryRecord>> query(HistoryQuery q) => _guard('query', () async {
        final where = <String>[];
        final args = <Object?>[];
        final search = q.search.trim();
        if (search.isNotEmpty) {
          final like = '%${search.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
          where.add(r"(title LIKE ? ESCAPE '\' OR playlist_title LIKE ? ESCAPE '\' "
              r"OR url LIKE ? ESCAPE '\' OR video_id LIKE ? ESCAPE '\')");
          args.addAll([like, like, like, like]);
        }
        if (q.status != null) {
          where.add('status = ?');
          args.add(q.status!.name);
        }
        if (q.from != null) {
          where.add('COALESCE(completed_at, created_at) >= ?');
          args.add(q.from!.millisecondsSinceEpoch);
        }
        if (q.to != null) {
          where.add('COALESCE(completed_at, created_at) < ?');
          args.add(q.to!.millisecondsSinceEpoch);
        }
        final rows = await _db.query(
          'history',
          where: where.isEmpty ? null : where.join(' AND '),
          whereArgs: args.isEmpty ? null : args,
          orderBy: 'COALESCE(completed_at, created_at) DESC, id DESC',
          limit: 5000,
        );
        return rows.map(fromRow).toList();
      });

  @override
  Future<void> delete(int id) =>
      _guard('delete', () => _db.delete('history', where: 'id = ?', whereArgs: [id]));

  @override
  Future<void> clear() => _guard('clear', () => _db.delete('history'));

  @override
  Future<int> markInterrupted() => _guard(
        'markInterrupted',
        () => _db.update(
          'history',
          {
            'status': HistoryStatus.interrupted.name,
            'error_message': 'CourseGrab was closed before this download finished.',
          },
          where: 'status = ?',
          whereArgs: [HistoryStatus.downloading.name],
        ),
      );
}
