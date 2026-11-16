import 'dart:async';
import 'dart:io';

import 'package:finder/core/errors/app_error.dart';
import 'package:finder/models/dependency_status.dart';
import 'package:finder/models/download_options.dart';
import 'package:finder/models/media_info.dart';
import 'package:finder/services/cancellation.dart';
import 'package:finder/services/downloader_service.dart';
import 'package:finder/services/ios/ios_bridge.dart';
import 'package:finder/services/ios/ios_downloader_service.dart';
import 'package:finder/services/ios/ios_metadata_service.dart';
import 'package:finder/services/ios/ios_platform_services.dart';
import 'package:finder/services/ios/resumable_writer.dart';
import 'package:finder/services/ios/stream_selection.dart';
import 'package:finder/services/ios/youtube_gateway.dart';
import 'package:finder/services/ios/youtube_link.dart';
import 'package:finder/services/process_service.dart';
import 'package:finder/core/utils/platform_info.dart';
import 'package:finder/services/ytdlp/ytdlp_args.dart';
import 'package:finder/services/ytdlp/ytdlp_output_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _vid = 'dQw4w9WgXcQ';
const _list = 'PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf';

StreamCandidate _video(
  int tag,
  int w,
  int h, {
  String codec = 'avc1.640028',
  String c = 'mp4',
  num fps = 30,
  int size = 4000,
}) => StreamCandidate(
  kind: StreamKind.videoOnly,
  tag: tag,
  container: c,
  videoCodec: codec,
  width: w,
  height: h,
  fps: fps,
  bitrate: w * 1000,
  size: size,
);
StreamCandidate _audio(int tag, int bitrate, {String c = 'mp4', int size = 1000}) => StreamCandidate(
  kind: StreamKind.audioOnly,
  tag: tag,
  container: c,
  audioCodec: c == 'mp4' ? 'mp4a.40.2' : 'opus',
  bitrate: bitrate,
  size: size,
);
StreamCandidate _muxed(int tag, int w, int h, {int size = 3000}) => StreamCandidate(
  kind: StreamKind.muxed,
  tag: tag,
  container: 'mp4',
  videoCodec: 'avc1',
  audioCodec: 'mp4a',
  width: w,
  height: h,
  size: size,
);

DownloadOptions _opts({
  VideoQuality q = VideoQuality.best,
  DownloadMode mode = DownloadMode.video,
  String dir = '/tmp',
}) => DownloadOptions(mode: mode, quality: q, destinationDir: dir);

void main() {
  group('YoutubeLink', () {
    test('watch?v=…&list=… follows the chosen scope', () {
      const url = 'https://www.youtube.com/watch?v=$_vid&list=$_list';
      expect(YoutubeLink.resolve(url, FetchScope.single), isA<YoutubeVideoTarget>());
      expect((YoutubeLink.resolve(url, FetchScope.playlist) as YoutubePlaylistTarget).playlistId, _list);
      expect(YoutubeLink.resolve(url, FetchScope.auto), isA<YoutubePlaylistTarget>());
    });

    test('recognizes short, shorts, embed and music links', () {
      for (final u in [
        'https://youtu.be/$_vid?t=3',
        'https://www.youtube.com/shorts/$_vid',
        'https://www.youtube.com/embed/$_vid',
        'https://music.youtube.com/watch?v=$_vid',
        'https://m.youtube.com/watch?v=$_vid',
      ]) {
        expect((YoutubeLink.resolve(u, FetchScope.auto) as YoutubeVideoTarget).videoId, _vid, reason: u);
      }
    });

    test('mixes (RD…) are read as the single video', () {
      final t = YoutubeLink.resolve('https://www.youtube.com/watch?v=$_vid&list=RD$_vid', FetchScope.auto);
      expect(t, isA<YoutubeVideoTarget>());
    });

    test('other sites are rejected with a clear message', () {
      expect(
        () => YoutubeLink.resolve('https://vimeo.com/123', FetchScope.auto),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.unsupportedSource)),
      );
    });

    test('scope mismatch is an invalid URL', () {
      expect(
        () => YoutubeLink.resolve('https://www.youtube.com/playlist?list=$_list', FetchScope.single),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.invalidUrl)),
      );
      expect(
        () => YoutubeLink.resolve('https://youtu.be/$_vid', FetchScope.playlist),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.invalidUrl)),
      );
    });
  });

  group('StreamSelector', () {
    final streams = [
      _video(137, 1920, 1080),
      _video(136, 1280, 720),
      _video(298, 1280, 720, fps: 60),
      _video(135, 854, 480),
      _video(248, 1920, 1080, codec: 'vp9', c: 'webm'), // not iOS-compatible
      _video(399, 1920, 1080, codec: 'av01.0.08M.08'), // AV1 in mp4: skipped
      _audio(140, 128000),
      _audio(139, 48000),
      _audio(251, 160000, c: 'webm'),
      _muxed(18, 640, 360),
    ];

    test('best quality = highest H.264 video + best AAC audio', () {
      final plan = StreamSelector.select(streams, _opts()) as SeparatePlan;
      expect(plan.video.tag, 137);
      expect(plan.audio.tag, 140);
      expect(plan.extension, 'mp4');
      expect(plan.resolution, 1080);
    });

    test('at or below the requested resolution, preferring higher fps', () {
      final plan = StreamSelector.select(streams, _opts(q: VideoQuality.p720)) as SeparatePlan;
      expect(plan.video.tag, 298);
    });

    test('falls back to the smallest stream above the target', () {
      final plan =
          StreamSelector.select([_video(137, 1920, 1080), _audio(140, 1)], _opts(q: VideoQuality.p360)) as SeparatePlan;
      expect(plan.video.tag, 137);
    });

    test('vertical video uses the short side', () {
      final plan = StreamSelector.select([
        _video(1, 1080, 1920),
        _video(2, 720, 1280),
        _audio(140, 1),
      ], _opts(q: VideoQuality.p720)) as SeparatePlan;
      expect(plan.video.tag, 2);
    });

    test('a muxed stream that is at least as good avoids muxing', () {
      final plan = StreamSelector.select(streams, _opts(q: VideoQuality.p360));
      expect(plan, isA<SinglePlan>());
      expect((plan as SinglePlan).stream.tag, 18);
    });

    test('audio only picks the best m4a', () {
      final plan = StreamSelector.select(streams, _opts(mode: DownloadMode.audioOnly)) as SinglePlan;
      expect(plan.stream.tag, 140);
      expect(plan.extension, 'm4a');
      expect(plan.resolution, isNull);
    });

    test('nothing compatible → null', () {
      expect(
        StreamSelector.select([_video(248, 1920, 1080, codec: 'vp9', c: 'webm'), _audio(251, 1, c: 'webm')], _opts()),
        isNull,
      );
    });

    test('formats exposed to the UI are only the ones iOS can save', () {
      final formats = streams.where((s) => s.isIosCompatible).map((s) => s.toMediaFormat()).toList();
      final entry = MediaEntry(id: 'x', title: 't', url: 'u', extractor: 'Youtube', formats: formats);
      expect(entry.maxResolution, 1080);
      expect(
        entry.availableQualities,
        containsAll([VideoQuality.p1080, VideoQuality.p720, VideoQuality.p480, VideoQuality.p360]),
      );
      expect(entry.availableQualities, isNot(contains(VideoQuality.p2160)));
    });
  });

  group('OutputName', () {
    test('renders the shared yt-dlp template', () {
      final t = YtDlpArgs.outputTemplate(playlistIndex: 7, numbered: true);
      expect(OutputName.render(t, title: 'A/B: 100%', id: _vid, ext: 'mp4'), '007 - A_B_ 100% [$_vid].mp4');
    });

    test('limits the title to 180 bytes', () {
      final name = OutputName.render(YtDlpArgs.outputTemplate(), title: 'é' * 300, id: _vid, ext: 'mp4');
      expect(name.startsWith('é' * 90), isTrue);
      expect(name.contains('é' * 91), isFalse);
    });
  });

  group('ResumableWriter', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('finder-ios'));
    tearDown(() async => tmp.delete(recursive: true));

    List<int> bytes(int n) => List.generate(n, (i) => i % 251);

    ByteSource sourceOf(List<int> data, {List<int>? starts, int chunk = 100}) => (start) async* {
      starts?.add(start);
      for (var i = start; i < data.length; i += chunk) {
        await Future<void>.delayed(Duration.zero);
        yield data.sublist(i, (i + chunk).clamp(0, data.length));
      }
    };

    test('writes the whole stream and reports real progress', () async {
      final data = bytes(1000);
      final file = File(p.join(tmp.path, 'a.part'));
      final seen = <WriteProgress>[];
      final r = await ResumableWriter(tick: Duration.zero)
          .write(partial: file, source: sourceOf(data), totalBytes: 1000, onProgress: seen.add);
      expect(r, WriteResult.completed);
      expect(await file.readAsBytes(), data);
      expect(seen.last.downloaded, 1000);
      expect(seen.map((e) => e.downloaded), orderedEquals([...seen.map((e) => e.downloaded)]..sort()));
    });

    test('continues from the partial file with a range offset', () async {
      final data = bytes(1000);
      final file = File(p.join(tmp.path, 'b.part'))..writeAsBytesSync(data.sublist(0, 400));
      final starts = <int>[];
      await ResumableWriter().write(
        partial: file,
        source: sourceOf(data, starts: starts),
        totalBytes: 1000,
        onProgress: (_) {},
      );
      expect(starts, [400]);
      expect(await file.readAsBytes(), data);
    });

    test('non-resumable streams restart from zero', () async {
      final data = bytes(500);
      final file = File(p.join(tmp.path, 'c.part'))..writeAsBytesSync([9, 9, 9]);
      final starts = <int>[];
      await ResumableWriter().write(
        partial: file,
        source: sourceOf(data, starts: starts),
        totalBytes: 500,
        onProgress: (_) {},
        resumable: false,
      );
      expect(starts, [0]);
      expect(await file.readAsBytes(), data);
    });

    test('stop keeps the partial data', () async {
      final ctrl = StreamController<List<int>>();
      final file = File(p.join(tmp.path, 'd.part'));
      final writer = ResumableWriter();
      final f = writer.write(partial: file, source: (_) => ctrl.stream, totalBytes: 1000, onProgress: (_) {});
      ctrl.add(bytes(300));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      writer.stop();
      expect(await f, WriteResult.stopped);
      expect(await file.length(), 300);
      await ctrl.close();
    });

    test('a connection that ends early is a network error', () async {
      final file = File(p.join(tmp.path, 'e.part'));
      await expectLater(
        ResumableWriter().write(partial: file, source: sourceOf(bytes(200)), totalBytes: 1000, onProgress: (_) {}),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.network)),
      );
      expect(await file.length(), 200); // kept for resume
    });
  });

  group('IosDownloaderService', () {
    late Directory tmp;
    late _FakeGateway gw;
    late _FakeMuxer muxer;
    late _FakeBackground bg;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('finder-ios');
      gw = _FakeGateway();
      muxer = _FakeMuxer();
      bg = _FakeBackground();
    });
    tearDown(() async => tmp.delete(recursive: true));

    DownloadJobSpec spec({
      DownloadMode mode = DownloadMode.video,
      VideoQuality q = VideoQuality.best,
      String url = 'https://www.youtube.com/watch?v=$_vid',
    }) => DownloadJobSpec(
      url: url,
      options: _opts(mode: mode, q: q, dir: tmp.path),
      directory: tmp.path,
      outputTemplate: YtDlpArgs.outputTemplate(),
      ytDlpPath: IosBuiltin.ytDlpPath,
      ffmpegPath: IosBuiltin.ffmpegPath,
    );

    IosDownloaderService svc() => IosDownloaderService(gateway: gw, muxer: muxer, background: bg);

    test('downloads video + audio, muxes, reports per-stream progress, cleans up', () async {
      final job = await svc().start(spec());
      final events = <YtDlpEvent>[];
      job.events.listen(events.add);
      final out = await job.outcome as DownloadSucceeded;
      expect(p.basename(out.filePath), 'Never Gonna [$_vid].mp4');
      expect(out.resolution, 1080);
      expect(await File(out.filePath).readAsString(), 'muxed');
      expect(muxer.calls, 1);
      final formatIds = events.whereType<ProgressEvent>().map((e) => e.formatId).toSet();
      expect(formatIds, {'137', '140'});
      expect(events.whereType<ProgressEvent>().where((e) => e.status == 'finished').length, 2);
      expect(events.whereType<PostProcessEvent>().first.label, 'Merging audio and video');
      expect(events.last, isA<FileEvent>());
      // Only the final file remains.
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['Never Gonna [$_vid].mp4']);
      expect(bg.begun, 1);
      expect(bg.ended, 1);
    });

    test('audio only saves the m4a without muxing', () async {
      final out = await (await svc().start(spec(mode: DownloadMode.audioOnly))).outcome as DownloadSucceeded;
      expect(out.filePath, endsWith('.m4a'));
      expect(out.extension, 'm4a');
      expect(muxer.calls, 0);
    });

    test('stop → DownloadStopped with partial kept; second run resumes from the offset', () async {
      gw.gate = Completer<void>();
      final job = await svc().start(spec());
      await gw.firstChunkSent.future;
      await job.stop();
      expect(await job.outcome, isA<DownloadStopped>());
      final parts = tmp.listSync().map((e) => p.basename(e.path)).where((n) => n.endsWith('.part')).toList();
      expect(parts, ['Never Gonna [$_vid].f137.mp4.part']);
      expect(job.announcedDestinations.single, endsWith('Never Gonna [$_vid].mp4'));

      gw.gate = null;
      gw.starts.clear();
      final out = await (await svc().start(spec())).outcome;
      expect(out, isA<DownloadSucceeded>());
      expect(gw.starts.first, greaterThan(0));
    });

    test('non-YouTube links fail with unsupportedSource', () async {
      final out = await (await svc().start(spec(url: 'https://vimeo.com/1'))).outcome as DownloadFailed;
      expect(out.error.kind, AppErrorKind.unsupportedSource);
    });

    test('mux failure is reported, not thrown', () async {
      muxer.fail = true;
      final out = await (await svc().start(spec())).outcome as DownloadFailed;
      expect(out.error.kind, AppErrorKind.ffmpeg);
    });
  });

  group('IosMetadataService', () {
    test('honours FetchScope for links with both v= and list=', () async {
      final gw = _FakeGateway();
      final svc = IosMetadataService(gw);
      const url = 'https://www.youtube.com/watch?v=$_vid&list=$_list';
      final single = await svc.fetch(url, ytDlpPath: IosBuiltin.ytDlpPath, scope: FetchScope.single);
      expect(single.isPlaylist, isFalse);
      expect(single.entries.single.stableId, 'youtube:$_vid');
      expect(single.entries.single.maxResolution, 1080);
      final list = await svc.fetch(url, ytDlpPath: IosBuiltin.ytDlpPath, scope: FetchScope.playlist);
      expect(list.isPlaylist, isTrue);
      expect(list.entries.map((e) => e.playlistIndex), [1, 2]);
      expect(list.entries.last.availability, EntryAvailability.live);
      expect(list.reportedCount, 2);
    });

    test('cancellation', () async {
      final gw = _FakeGateway()..slow = true;
      final token = CancellationToken();
      final f = IosMetadataService(gw).fetch('https://youtu.be/$_vid', ytDlpPath: '', cancel: token);
      token.cancel();
      await expectLater(f, throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.cancelled)));
    });
  });

  test('IosDependencyManager reports the built-in engine as ready and never installs', () async {
    final m = IosDependencyManager(
      platform: const PlatformInfo(os: HostOs.ios, arch: HostArch.arm64, resolvedExecutable: '/x', environment: {}),
      processes: ProcessService.forHost(),
      managedBinDir: '/nonexistent',
    );
    final s = await m.snapshot();
    expect(s.allReady, isTrue);
    expect(s.ytDlp.source, DependencySource.bundled);
    expect(m.canInstall(DependencyKind.ytDlp), isFalse);
    expect(m.canUpdate(s.ytDlp), isFalse);
  });
}

class _FakeGateway implements YoutubeGateway {
  Completer<void>? gate;
  var firstChunkSent = Completer<void>();
  final starts = <int>[];
  bool slow = false;

  final _streams = [
    _video(137, 1920, 1080, size: 600),
    _video(136, 1280, 720, size: 400),
    _audio(140, 128000, size: 300),
    _muxed(18, 640, 360, size: 200),
  ];

  @override
  Future<YoutubeVideoDetails> video(String id) async {
    if (slow) await Future<void>.delayed(const Duration(seconds: 5));
    return YoutubeVideoDetails(id: id, title: 'Never Gonna', author: 'Rick', duration: const Duration(seconds: 212));
  }

  @override
  Future<List<StreamCandidate>> streams(String videoId) async => _streams;

  @override
  Future<YoutubePlaylistDetails> playlist(String id) async =>
      YoutubePlaylistDetails(id: id, title: 'Mix', author: 'Me', videoCount: 2);

  @override
  Stream<YoutubeVideoDetails> playlistVideos(String id) => Stream.fromIterable(const [
    YoutubeVideoDetails(id: 'aaaaaaaaaaa', title: 'One'),
    YoutubeVideoDetails(id: 'bbbbbbbbbbb', title: 'Two', isLive: true),
  ]);

  @override
  ByteSource open(StreamCandidate stream) => (start) async* {
    starts.add(start);
    final total = stream.size!;
    for (var i = start; i < total; i += 100) {
      final n = (i + 100).clamp(0, total) - i;
      yield List.filled(n, 1);
      if (!firstChunkSent.isCompleted) firstChunkSent.complete();
      final g = gate;
      if (g != null) await g.future;
    }
  };

  @override
  bool isResumable(StreamCandidate stream) => true;
}

class _FakeMuxer implements Muxer {
  int calls = 0;
  bool fail = false;
  @override
  Future<int?> mux({required String videoPath, required String audioPath, required String outputPath}) async {
    calls++;
    expect(File(videoPath).existsSync(), isTrue);
    expect(File(audioPath).existsSync(), isTrue);
    if (fail) throw PlatformException(code: 'mux', message: 'export failed');
    await File(outputPath).writeAsString('muxed');
    return 1080;
  }
}

class _FakeBackground implements BackgroundTasks {
  int begun = 0, ended = 0;
  @override
  Future<int?> begin(String name) async => ++begun;
  @override
  Future<void> end(int? id) async => ended++;
}
