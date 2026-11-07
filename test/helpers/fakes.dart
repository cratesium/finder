import 'dart:async';

import 'package:coursegrab/core/errors/app_error.dart';
import 'package:coursegrab/features/history/data/history_repository.dart';
import 'package:coursegrab/features/settings/application/dependency_controller.dart';
import 'package:coursegrab/features/settings/data/settings_repository.dart';
import 'package:coursegrab/models/app_settings.dart';
import 'package:coursegrab/models/dependency_status.dart';
import 'package:coursegrab/models/download_options.dart';
import 'package:coursegrab/models/download_task.dart';
import 'package:coursegrab/models/history_record.dart';
import 'package:coursegrab/models/media_info.dart';
import 'package:coursegrab/services/cancellation.dart';
import 'package:coursegrab/services/directory_picker.dart';
import 'package:coursegrab/services/downloader_service.dart';
import 'package:coursegrab/services/file_opener_service.dart';
import 'package:coursegrab/services/metadata_service.dart';
import 'package:coursegrab/services/notification_service.dart';
import 'package:coursegrab/services/trust_store_service.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_output_parser.dart';

MediaEntry entry(
  String id, {
  String? title,
  int? index,
  EntryAvailability availability = EntryAvailability.available,
  Duration? duration = const Duration(minutes: 3),
  List<MediaFormat> formats = const [],
}) =>
    MediaEntry(
      id: id,
      title: title ?? 'Video $id',
      url: 'https://www.youtube.com/watch?v=$id',
      extractor: 'Youtube',
      playlistIndex: index,
      duration: duration,
      availability: availability,
      formats: formats,
    );

DownloadRequest request(String id, {String dir = '/tmp/cg-test', DownloadOptions? options, String? playlist}) =>
    DownloadRequest(
      entry: entry(id),
      options: options ?? DownloadOptions(destinationDir: dir),
      playlistTitle: playlist,
    );

/// In-memory history repository.
class FakeHistoryRepository implements HistoryRepository {
  final Map<String, HistoryRecord> byKey = {};
  int _id = 0;
  bool failWrites = false;

  @override
  Future<int> upsert(HistoryRecord record) async {
    if (failWrites) throw AppError.of(AppErrorKind.storage);
    final existing = byKey[record.dedupeKey];
    final id = existing?.id ?? ++_id;
    byKey[record.dedupeKey] = record.copyWith(id: id);
    return id;
  }

  @override
  Future<HistoryRecord?> findByDedupeKey(String key) async => byKey[key];

  @override
  Future<List<HistoryRecord>> query(HistoryQuery query) async {
    return byKey.values.where((r) {
      if (query.status != null && r.status != query.status) return false;
      if (query.search.isNotEmpty && !r.title.toLowerCase().contains(query.search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<void> delete(int id) async => byKey.removeWhere((_, r) => r.id == id);

  @override
  Future<void> clear() async => byKey.clear();

  @override
  Future<int> markInterrupted() async => 0;
}

class FakeSettingsRepository implements SettingsRepository {
  AppSettings? saved;
  @override
  Future<AppSettings> load({required String fallbackDirectory}) async =>
      saved ?? AppSettings(downloadDirectory: fallbackDirectory);
  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

/// A download job driven manually by the test.
class FakeJob implements DownloadJob {
  FakeJob(this.spec);

  final DownloadJobSpec spec;
  final _events = StreamController<YtDlpEvent>.broadcast();
  final _outcome = Completer<DownloadOutcome>();
  bool stopped = false;

  @override
  Stream<YtDlpEvent> get events => _events.stream;

  @override
  Future<DownloadOutcome> get outcome => _outcome.future;

  @override
  List<String> get announcedDestinations => const [];

  void emit(YtDlpEvent e) => _events.add(e);

  void succeed(String path, {int? res, String? ext = 'mp4'}) {
    if (_outcome.isCompleted) return;
    _events.close();
    _outcome.complete(DownloadSucceeded(filePath: path, resolution: res, extension: ext));
  }

  void fail(AppError error) {
    if (_outcome.isCompleted) return;
    _events.close();
    _outcome.complete(DownloadFailed(error));
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_outcome.isCompleted) {
      _events.close();
      _outcome.complete(const DownloadStopped());
    }
  }
}

class FakeDownloader implements DownloaderService {
  final List<FakeJob> jobs = [];
  final _started = StreamController<FakeJob>.broadcast();
  Stream<FakeJob> get started => _started.stream;
  AppError? startError;

  @override
  Future<DownloadJob> start(DownloadJobSpec spec) async {
    if (startError != null) throw startError!;
    final job = FakeJob(spec);
    jobs.add(job);
    _started.add(job);
    return job;
  }

  List<FakeJob> get running => jobs.where((j) => !j._outcome.isCompleted).toList();
}

class FakeMetadataService implements MetadataService {
  FakeMetadataService(this.result);
  FutureOr<MediaInfo> Function(String url) result;
  int calls = 0;

  @override
  Future<MediaInfo> fetch(String url,
      {required String ytDlpPath, CancellationToken? cancel, YtDlpNetworkConfig network = YtDlpNetworkConfig.none}) async {
    calls++;
    return result(url);
  }
}

class FakeNotifications implements NotificationService {
  final shown = <String>[];
  @override
  Future<void> show({required String title, required String body}) async => shown.add('$title: $body');
}

class FakeFileOpener implements FileOpenerService {
  final opened = <String>[];
  @override
  Future<void> openFile(String path) async => opened.add('open:$path');
  @override
  Future<void> openFolder(String path) async => opened.add('folder:$path');
  @override
  Future<void> revealInFolder(String path) async => opened.add('reveal:$path');
}

class FakeDirectoryPicker implements DirectoryPicker {
  FakeDirectoryPicker({this.directory, this.executable});
  String? directory;
  String? executable;
  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => directory;
  @override
  Future<String?> pickExecutable({String? initialDirectory}) async => executable;
}

const readySnapshot = DependencySnapshot(
  ytDlp: DependencyStatus(
    kind: DependencyKind.ytDlp,
    state: DependencyState.ready,
    path: '/fake/yt-dlp',
    version: '2026.10.26',
    source: DependencySource.managed,
  ),
  ffmpeg: DependencyStatus(
    kind: DependencyKind.ffmpeg,
    state: DependencyState.ready,
    path: '/fake/ffmpeg',
    version: '7.1',
    source: DependencySource.system,
  ),
);

const missingSnapshot = DependencySnapshot(
  ytDlp: DependencyStatus.missing(DependencyKind.ytDlp, message: 'yt-dlp was not found.'),
  ffmpeg: DependencyStatus.missing(DependencyKind.ffmpeg, message: 'FFmpeg was not found.'),
);

class FakeDependencyController extends DependencyController {
  FakeDependencyController(this.snapshot);
  final DependencySnapshot snapshot;

  @override
  Future<DependencySnapshot> build() async => snapshot;

  @override
  Future<void> recheck() async {}
}
