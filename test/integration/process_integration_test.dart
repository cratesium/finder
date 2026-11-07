@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:coursegrab/core/errors/app_error.dart';
import 'package:coursegrab/core/utils/platform_info.dart';
import 'package:coursegrab/models/dependency_status.dart';
import 'package:coursegrab/models/download_options.dart';
import 'package:coursegrab/models/media_info.dart';
import 'package:coursegrab/services/binary_installer.dart';
import 'package:coursegrab/services/cancellation.dart';
import 'package:coursegrab/services/dependency_manager.dart';
import 'package:coursegrab/services/downloader_service.dart';
import 'package:coursegrab/services/metadata_service.dart';
import 'package:coursegrab/services/process_service.dart';
import 'package:coursegrab/services/trust_store_service.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_args.dart';
import 'package:coursegrab/services/ytdlp/ytdlp_output_parser.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/mock_executables.dart';

bool isAlive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late Directory tmp;
  late ProcessService processes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cg-int');
    processes = ProcessService();
  });

  tearDown(() async {
    await processes.killAll();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ProcessService lifecycle', () {
    test('captures stdout, stderr and exit code', () async {
      final exe = await writeScript(tmp, 'echo.sh', 'echo out; echo err 1>&2; exit 3');
      final r = await processes.run(exe, const []);
      expect(r.exitCode, 3);
      expect(r.stdout.trim(), 'out');
      expect(r.stderr.trim(), 'err');
      expect(r.ok, isFalse);
    });

    test('arguments are passed verbatim, never through a shell', () async {
      final marker = p.join(tmp.path, 'pwned');
      final exe = await writeScript(tmp, 'args.sh', r'for a in "$@"; do echo "[$a]"; done');
      final hostile = ['\$(touch $marker)', '; touch $marker', '`touch $marker`', 'a b  c', '&& echo hi', "it's"];
      final r = await processes.run(exe, hostile);
      expect(r.stdout.trim().split('\n'), hostile.map((a) => '[$a]').toList());
      expect(File(marker).existsSync(), isFalse);
    });

    test('times out and kills hung processes', () async {
      final exe = await writeScript(tmp, 'hang.sh', 'sleep 30');
      final sw = Stopwatch()..start();
      final r = await processes.run(exe, const [], timeout: const Duration(milliseconds: 300));
      expect(r.timedOut, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
      expect(processes.liveCount, 0);
    });

    test('terminate kills the whole process tree (no orphans)', () async {
      final exe = await writeScript(tmp, 'tree.sh', r'sleep 30 & echo "child:$!"; wait');
      final proc = await processes.start(exe, const []);
      final childPid = int.parse((await proc.stdoutLines.first).split(':').last);
      expect(isAlive(childPid), isTrue);
      await proc.terminate(grace: const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(isAlive(proc.pid), isFalse);
      expect(isAlive(childPid), isFalse);
    });

    test('processes ignoring SIGINT are force-killed after the grace period', () async {
      final exe = await writeScript(tmp, 'stubborn.sh', "trap '' INT; echo ready; while true; do sleep 1; done");
      final proc = await processes.start(exe, const []);
      await proc.stdoutLines.first;
      await proc.terminate(grace: const Duration(milliseconds: 400));
      final code = await proc.exitCode.timeout(const Duration(seconds: 5));
      expect(code, isNot(0));
    });

    test('killAll cleans up every live child', () async {
      final exe = await writeScript(tmp, 'sleep.sh', 'echo up; sleep 30');
      final a = await processes.start(exe, const []);
      final b = await processes.start(exe, const []);
      await Future.wait([a.stdoutLines.first, b.stdoutLines.first]);
      expect(processes.liveCount, 2);
      await processes.killAll(grace: const Duration(milliseconds: 300));
      expect(isAlive(a.pid), isFalse);
      expect(isAlive(b.pid), isFalse);
    });

    test('missing executables raise ProcessException', () async {
      expect(() => processes.start(p.join(tmp.path, 'nope'), const []), throwsA(isA<ProcessException>()));
    });
  });

  group('YtDlpDownloaderService with a mock yt-dlp', () {
    late String ytDlp;
    late Directory out;

    setUp(() async {
      ytDlp = await writeScript(tmp, 'yt-dlp', fakeYtDlpScript);
      out = await Directory(p.join(tmp.path, 'out dir')).create();
    });

    DownloadJobSpec spec(String url) => DownloadJobSpec(
          url: url,
          options: DownloadOptions(destinationDir: out.path),
          directory: out.path,
          outputTemplate: YtDlpArgs.outputTemplate(),
          ytDlpPath: ytDlp,
        );

    test('parses real progress output and reports the finished file', () async {
      final job = await YtDlpDownloaderService(processes).start(spec('https://fake.test/ok'));
      final events = <YtDlpEvent>[];
      final sub = job.events.listen(events.add);
      final outcome = await job.outcome;
      await sub.cancel();

      expect(outcome, isA<DownloadSucceeded>());
      final s = outcome as DownloadSucceeded;
      expect(s.filePath, p.join(out.path, 'Fake Video [ok1].mp4'));
      expect(File(s.filePath).existsSync(), isTrue);
      expect(s.resolution, 720);
      final progress = events.whereType<ProgressEvent>().toList();
      expect(progress, hasLength(5));
      expect(progress[1].downloadedBytes, 500);
      expect(progress[1].speed, 250);
      expect(progress.map((e) => e.formatId).toSet(), {'137', '140'});
      expect(events.whereType<PostProcessEvent>().first.postprocessor, 'Merger');
      expect(job.announcedDestinations.single, endsWith('Fake Video [ok1].mp4'));
    });

    test('classifies failures from stderr', () async {
      final job = await YtDlpDownloaderService(processes).start(spec('https://fake.test/private'));
      final outcome = await job.outcome;
      expect(outcome, isA<DownloadFailed>());
      expect((outcome as DownloadFailed).error.kind, AppErrorKind.inaccessible);
    });

    test('stop terminates yt-dlp and its children', () async {
      final job = await YtDlpDownloaderService(processes).start(spec('https://fake.test/slow'));
      await job.events.firstWhere((e) => e is ProgressEvent);
      await job.stop();
      final outcome = await job.outcome.timeout(const Duration(seconds: 10));
      expect(outcome, isA<DownloadStopped>());
      expect(processes.liveCount, 0);
    });

    test('a missing executable is reported as a missing dependency', () async {
      final bad = DownloadJobSpec(
        url: 'https://fake.test/ok',
        options: DownloadOptions(destinationDir: out.path),
        directory: out.path,
        outputTemplate: 'x',
        ytDlpPath: p.join(tmp.path, 'missing-yt-dlp'),
      );
      expect(
        () => YtDlpDownloaderService(processes).start(bad),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.missingDependency)),
      );
    });
  });

  group('YtDlpMetadataService with a mock yt-dlp', () {
    late String ytDlp;
    setUp(() async => ytDlp = await writeScript(tmp, 'yt-dlp', fakeYtDlpScript));

    test('extracts a playlist', () async {
      final info = await YtDlpMetadataService(processes).fetch('https://fake.test/meta-playlist', ytDlpPath: ytDlp);
      expect(info.kind, MediaKind.playlist);
      expect(info.title, 'Fake Course');
      expect(info.totalCount, 2);
      expect(info.downloadableCount, 1);
    });

    test('extracts a single video with formats', () async {
      final info = await YtDlpMetadataService(processes).fetch('https://fake.test/meta-video', ytDlpPath: ytDlp);
      expect(info.kind, MediaKind.video);
      expect(info.entries.single.availableQualities, contains(VideoQuality.p360));
    });

    test('maps errors to friendly messages', () async {
      expect(
        () => YtDlpMetadataService(processes).fetch('https://fake.test/unknown', ytDlpPath: ytDlp),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.unsupportedSource)),
      );
    });

    test('a "null" result with an error exit uses the stderr diagnosis', () async {
      expect(
        () => YtDlpMetadataService(processes).fetch('https://fake.test/meta-null', ytDlpPath: ytDlp),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.unavailable)),
      );
    });

    test('network config adds args and environment to the process', () async {
      final echo = await writeScript(tmp, 'yt-dlp-env',
          r'printf "{\"id\":\"e\",\"title\":\"%s|%s\",\"webpage_url\":\"https://x.test/e\"}" "$SSL_CERT_FILE" "$*"');
      final info = await YtDlpMetadataService(processes).fetch('https://x.test/e',
          ytDlpPath: echo,
          network: const YtDlpNetworkConfig(useSystemCertificates: true, caBundlePath: '/certs/roots.pem'));
      expect(info.title, startsWith('/certs/roots.pem|'));
      expect(info.title, contains('--compat-options no-certifi'));
    });

    test('can be cancelled', () async {
      final slow = await writeScript(tmp, 'yt-dlp-slow', 'sleep 30');
      final token = CancellationToken();
      final f = YtDlpMetadataService(processes).fetch('https://fake.test/x', ytDlpPath: slow, cancel: token);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      token.cancel();
      await expectLater(f, throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.cancelled)));
    });

    test('times out', () async {
      final slow = await writeScript(tmp, 'yt-dlp-slow', 'sleep 30');
      final svc = YtDlpMetadataService(processes, timeout: const Duration(milliseconds: 300));
      await expectLater(svc.fetch('https://fake.test/x', ytDlpPath: slow),
          throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.timeout)));
    });
  });

  group('DependencyManager', () {
    late Directory managed, pathDir;

    DependencyManager manager({List<String> path = const []}) => DependencyManager(
          platform: PlatformInfo(
            os: HostOs.macos,
            arch: HostArch.arm64,
            resolvedExecutable: p.join(tmp.path, 'App.app', 'Contents', 'MacOS', 'CourseGrab'),
            environment: {'PATH': path.join(':'), 'HOME': tmp.path},
          ),
          processes: processes,
          managedBinDir: managed.path,
        );

    setUp(() async {
      managed = await Directory(p.join(tmp.path, 'managed')).create();
      pathDir = await Directory(p.join(tmp.path, 'pathdir')).create();
    });

    test('validates a real executable and reads its version', () async {
      final exe = await writeScript(pathDir, 'yt-dlp', fakeYtDlpScript);
      final s = await manager().validate(DependencyKind.ytDlp, exe, DependencySource.custom);
      expect(s.isReady, isTrue);
      expect(s.version, '2026.10.26');
    });

    test('rejects wrong names, non-executables, relative paths and impostors', () async {
      final m = manager();
      final wrongName = await writeScript(pathDir, 'evil', fakeYtDlpScript);
      expect((await m.validate(DependencyKind.ytDlp, wrongName, DependencySource.custom)).state,
          DependencyState.invalid);

      final notExec = await writeScript(pathDir, 'yt-dlp-noexec', fakeYtDlpScript, executable: false);
      final ne = await m.validate(DependencyKind.ytDlp, notExec, DependencySource.custom);
      expect(ne.state, DependencyState.invalid);
      expect(ne.message, contains('not executable'));

      expect((await m.validate(DependencyKind.ytDlp, 'yt-dlp', DependencySource.custom)).state,
          DependencyState.invalid);

      final impostor = await writeScript(pathDir, 'yt-dlp-fake', 'echo hello');
      expect((await m.validate(DependencyKind.ytDlp, impostor, DependencySource.custom)).state,
          DependencyState.invalid);

      expect((await m.validate(DependencyKind.ytDlp, p.join(pathDir.path, 'none'), DependencySource.custom)).state,
          DependencyState.invalid);
    });

    test('resolution prefers the managed copy over PATH', () async {
      await writeScript(pathDir, 'yt-dlp', fakeYtDlpScript);
      var s = await manager(path: [pathDir.path]).resolve(DependencyKind.ytDlp);
      expect(s.source, DependencySource.system);
      await writeScript(managed, 'yt-dlp', fakeYtDlpScript);
      s = await manager(path: [pathDir.path]).resolve(DependencyKind.ytDlp);
      expect(s.source, DependencySource.managed);
    });

    test('custom paths are never silently replaced', () async {
      await writeScript(managed, 'yt-dlp', fakeYtDlpScript);
      final s = await manager().resolve(DependencyKind.ytDlp, customPath: p.join(tmp.path, 'missing', 'yt-dlp'));
      expect(s.state, DependencyState.invalid);
      expect(s.source, DependencySource.custom);
    });

    test('reports missing tools with guidance', () async {
      final m = manager();
      final snap = await m.snapshot();
      expect(snap.ytDlp.state, DependencyState.missing);
      expect(snap.ffmpeg.state, DependencyState.missing);
      expect(m.guidance(DependencyKind.ffmpeg), contains('FFmpeg'));
      expect(m.canInstall(DependencyKind.ytDlp), isTrue);
      expect(m.canInstall(DependencyKind.ffmpeg), isFalse); // no official macOS build
    });

    test('ffmpeg validation warns when ffprobe is missing', () async {
      final ff = await writeScript(pathDir, 'ffmpeg', fakeFfmpegScript);
      var s = await manager().validate(DependencyKind.ffmpeg, ff, DependencySource.system);
      expect(s.isReady, isTrue);
      expect(s.version, '7.1.1');
      expect(s.message, contains('ffprobe'));
      await writeScript(pathDir, 'ffprobe', fakeFfmpegScript);
      s = await manager().validate(DependencyKind.ffmpeg, ff, DependencySource.system);
      expect(s.message, isNull);
    });
  });

  group('TrustStoreService', () {
    PlatformInfo host(HostOs os) =>
        PlatformInfo(os: os, arch: HostArch.x64, resolvedExecutable: '/x', environment: const {});

    test('disabled means yt-dlp defaults', () async {
      final c = await TrustStoreService(platform: host(HostOs.macos), dataDir: tmp.path)
          .build(useSystemCertificates: false);
      expect(c.arguments, isEmpty);
      expect(c.environment, isEmpty);
    });

    test('Windows uses the OS store without a bundle', () async {
      final c = await TrustStoreService(platform: host(HostOs.windows), dataDir: tmp.path)
          .build(useSystemCertificates: true);
      expect(c.arguments, ['--compat-options', 'no-certifi']);
      expect(c.environment, isEmpty);
    });

    test('macOS exports keychain roots to a PEM bundle', () async {
      final c = await TrustStoreService(platform: host(HostOs.macos), dataDir: tmp.path)
          .build(useSystemCertificates: true);
      expect(c.caBundlePath, isNotNull);
      expect(File(c.caBundlePath!).readAsStringSync(), contains('BEGIN CERTIFICATE'));
      expect(c.environment['SSL_CERT_FILE'], c.caBundlePath);
    }, testOn: 'mac-os');
  });

  group('BinaryInstaller (local HTTPS stand-in)', () {
    late HttpServer server;
    late String base;
    final payload = List<int>.generate(4096, (i) => i % 251);

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      final good = sha256.convert(payload).toString();
      server.listen((req) {
        final res = req.response;
        switch (req.uri.path) {
          case '/SUMS':
            res.write('$good  tool\n${'0' * 64}  tampered\n');
          case '/tool':
          case '/tampered':
            res.contentLength = payload.length;
            res.add(payload);
          default:
            res.statusCode = 404;
        }
        res.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('installs a file whose checksum matches', () async {
      final target = File(p.join(tmp.path, 'bin', 'tool'));
      final progress = <double?>[];
      await BinaryInstaller().installAsset(
        releaseBase: base,
        checksumsUrl: Uri.parse('$base/SUMS'),
        assetName: 'tool',
        target: target,
        onProgress: (f, _) => progress.add(f),
      );
      expect(await target.readAsBytes(), payload);
      expect(progress.last, 1);
    });

    test('discards a file whose checksum does not match', () async {
      final target = File(p.join(tmp.path, 'bin', 'tampered'));
      await expectLater(
        BinaryInstaller().installAsset(
          releaseBase: base,
          checksumsUrl: Uri.parse('$base/SUMS'),
          assetName: 'tampered',
          target: target,
        ),
        throwsA(isA<AppError>().having((e) => e.message, 'message', contains('checksum'))),
      );
      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.download').existsSync(), isFalse);
    });

    test('refuses assets without a published checksum', () async {
      await expectLater(
        BinaryInstaller().installAsset(
          releaseBase: base,
          checksumsUrl: Uri.parse('$base/SUMS'),
          assetName: 'unlisted',
          target: File(p.join(tmp.path, 'unlisted')),
        ),
        throwsA(isA<AppError>()),
      );
    });

    test('retries dropped connections, then succeeds', () async {
      var calls = 0;
      final good = sha256.convert(payload).toString();
      // Raw socket server so a response can be cut off mid-body.
      final flaky = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      flaky.listen((socket) async {
        final request = await socket.cast<List<int>>().transform(const SystemEncoding().decoder).first;
        final path = request.split(' ')[1];
        List<int> body;
        var truncate = false;
        if (path == '/SUMS') {
          body = '$good  tool\n'.codeUnits;
        } else {
          calls++;
          body = payload;
          truncate = calls < 3;
        }
        socket.add('HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n'.codeUnits);
        socket.add(truncate ? body.sublist(0, 10) : body);
        await socket.flush();
        socket.destroy();
      });
      final fb = 'http://127.0.0.1:${flaky.port}';
      final target = File(p.join(tmp.path, 'flaky', 'tool'));
      await BinaryInstaller(retryDelay: Duration.zero).installAsset(
        releaseBase: fb,
        checksumsUrl: Uri.parse('$fb/SUMS'),
        assetName: 'tool',
        target: target,
      );
      expect(calls, 3);
      expect(await target.readAsBytes(), payload);
      await flaky.close();
    });

    test('a stalled connection times out instead of hanging', () async {
      final stall = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      stall.listen((socket) {
        sockets.add(socket);
        // Send headers and a few bytes, then go silent forever.
        socket.add('HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\nabc'.codeUnits);
      });
      final sw = Stopwatch()..start();
      await expectLater(
        BinaryInstaller(maxAttempts: 1, idleTimeout: const Duration(milliseconds: 400)).downloadVerified(
          url: Uri.parse('http://127.0.0.1:${stall.port}/x'),
          expectedSha256: '0' * 64,
          target: File(p.join(tmp.path, 'stall', 'x')),
        ),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.network)),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(File(p.join(tmp.path, 'stall', 'x.download')).existsSync(), isFalse);
      for (final s in sockets) {
        s.destroy();
      }
      await stall.close();
    });

    test('HTTP errors become network errors', () async {
      await expectLater(
        BinaryInstaller().fetchText(Uri.parse('$base/missing')),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.network)),
      );
    });
  });
}
