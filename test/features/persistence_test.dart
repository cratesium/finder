import 'package:finder/features/history/data/history_repository.dart';
import 'package:finder/features/settings/data/settings_repository.dart';
import 'package:finder/models/app_settings.dart';
import 'package:finder/models/download_options.dart';
import 'package:finder/models/history_record.dart';
import 'package:finder/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

HistoryRecord record(String key,
        {String title = 'Title', HistoryStatus status = HistoryStatus.completed, DateTime? at, String? playlist}) =>
    HistoryRecord(
      dedupeKey: key,
      videoId: key,
      extractor: 'Youtube',
      title: title,
      url: 'https://youtube.com/watch?v=$key',
      destinationDir: '/d',
      status: status,
      createdAt: at ?? DateTime(2026, 1, 1),
      completedAt: status == HistoryStatus.completed ? (at ?? DateTime(2026, 1, 1)) : null,
      options: const DownloadOptions(destinationDir: '/d', quality: VideoQuality.p720),
      playlistTitle: playlist,
      resolution: '720p',
      format: 'mp4',
      fileSize: 42,
      filePath: '/d/$key.mp4',
    );

void main() {
  late Database db;

  setUp(() async {
    db = await StorageService.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
  });

  tearDown(() => db.close());

  group('SqliteHistoryRepository', () {
    test('upsert inserts then updates by dedupe key', () async {
      final repo = SqliteHistoryRepository(db);
      final id1 = await repo.upsert(record('a', status: HistoryStatus.downloading));
      final id2 = await repo.upsert(record('a', status: HistoryStatus.completed));
      expect(id1, id2);
      final all = await repo.query(const HistoryQuery());
      expect(all, hasLength(1));
      expect(all.single.status, HistoryStatus.completed);
      expect(all.single.options.quality, VideoQuality.p720);
      expect(all.single.fileSize, 42);
    });

    test('find by dedupe key', () async {
      final repo = SqliteHistoryRepository(db);
      await repo.upsert(record('a'));
      expect((await repo.findByDedupeKey('a'))!.title, 'Title');
      expect(await repo.findByDedupeKey('missing'), isNull);
    });

    test('search matches title/playlist and escapes wildcards', () async {
      final repo = SqliteHistoryRepository(db);
      await repo.upsert(record('a', title: 'Flutter basics'));
      await repo.upsert(record('b', title: 'Dart', playlist: 'Flutter course'));
      await repo.upsert(record('c', title: '100% done'));
      await repo.upsert(record('d', title: '100 items'));
      expect((await repo.query(const HistoryQuery(search: 'flutter'))).map((r) => r.videoId).toSet(), {'a', 'b'});
      expect((await repo.query(const HistoryQuery(search: '100%'))).map((r) => r.videoId), ['c']);
    });

    test('filters by status and date', () async {
      final repo = SqliteHistoryRepository(db);
      await repo.upsert(record('old', at: DateTime(2025, 1, 1)));
      await repo.upsert(record('new', at: DateTime(2026, 6, 1)));
      await repo.upsert(record('bad', status: HistoryStatus.failed, at: DateTime(2026, 6, 2)));
      expect((await repo.query(const HistoryQuery(status: HistoryStatus.failed))).single.videoId, 'bad');
      final ranged = await repo.query(HistoryQuery(from: DateTime(2026), to: DateTime(2026, 6, 2)));
      expect(ranged.map((r) => r.videoId), ['new']);
    });

    test('orders newest first, deletes and clears', () async {
      final repo = SqliteHistoryRepository(db);
      await repo.upsert(record('a', at: DateTime(2026, 1, 1)));
      await repo.upsert(record('b', at: DateTime(2026, 2, 1)));
      final all = await repo.query(const HistoryQuery());
      expect(all.map((r) => r.videoId), ['b', 'a']);
      await repo.delete(all.first.id!);
      expect((await repo.query(const HistoryQuery())).single.videoId, 'a');
      await repo.clear();
      expect(await repo.query(const HistoryQuery()), isEmpty);
    });

    test('marks unfinished downloads from a previous session as interrupted', () async {
      final repo = SqliteHistoryRepository(db);
      await repo.upsert(record('a', status: HistoryStatus.downloading));
      await repo.upsert(record('b'));
      expect(await repo.markInterrupted(), 1);
      expect((await repo.findByDedupeKey('a'))!.status, HistoryStatus.interrupted);
      expect((await repo.findByDedupeKey('b'))!.status, HistoryStatus.completed);
    });

    test('database errors become friendly storage errors', () async {
      final repo = SqliteHistoryRepository(db);
      await db.close();
      await expectLater(repo.query(const HistoryQuery()), throwsA(anything));
    });
  });

  group('SqliteSettingsRepository', () {
    test('returns defaults when empty and persists changes', () async {
      final repo = SqliteSettingsRepository(db);
      final initial = await repo.load(fallbackDirectory: '/dl');
      expect(initial.downloadDirectory, '/dl');
      expect(initial.theme, ThemePreference.dark);

      await repo.save(initial.copyWith(
        maxConcurrentDownloads: 4,
        theme: ThemePreference.light,
        ffmpegPath: () => '/opt/ffmpeg',
      ));
      final loaded = await repo.load(fallbackDirectory: '/dl');
      expect(loaded.maxConcurrentDownloads, 4);
      expect(loaded.theme, ThemePreference.light);
      expect(loaded.ffmpegPath, '/opt/ffmpeg');

      await repo.save(loaded.copyWith(ffmpegPath: () => null));
      expect((await repo.load(fallbackDirectory: '/dl')).ffmpegPath, isNull);
    });

    test('corrupted settings fall back to defaults', () async {
      await db.insert('settings', {'key': 'app_settings', 'value': '{not json'});
      final s = await SqliteSettingsRepository(db).load(fallbackDirectory: '/dl');
      expect(s.downloadDirectory, '/dl');
    });
  });
}
