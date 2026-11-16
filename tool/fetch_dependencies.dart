// Downloads official, checksum-verified yt-dlp and FFmpeg builds that are
// bundled INSIDE the Finder app, so end users never need to install either.
// Nothing is used without SHA-256 verification.
//
//   dart run tool/fetch_dependencies.dart --platform macos   [--arch universal|arm64|x64] [--ffmpeg /path/to/ffmpeg]
//   dart run tool/fetch_dependencies.dart --platform windows [--arch x64|arm64]
//   dart run tool/fetch_dependencies.dart --platform linux   [--arch x64|arm64]
//
// Output: third_party/<platform>/bin/
//   macos:   yt-dlp_macos/yt-dlp_macos (+ _internal), ffmpeg, ffprobe
//            (universal by default: arm64 + x64 merged with lipo)
//   windows: yt-dlp/yt-dlp.exe (+ _internal), ffmpeg.exe, ffprobe.exe, FFMPEG-LICENSE.txt
//   linux:   yt-dlp_linux/yt-dlp_linux[_aarch64] (+ _internal), ffmpeg, ffprobe, FFMPEG-LICENSE.txt
//            (needs `unzip` or `bsdtar`, and `tar` with xz support)
import 'dart:io';

import 'package:finder/core/config/app_config.dart';
import 'package:finder/services/binary_installer.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final platform = opt('platform');
  if (platform != 'windows' && platform != 'macos' && platform != 'linux') {
    stderr.writeln('usage: dart run tool/fetch_dependencies.dart --platform windows|macos|linux '
        '[--arch universal|arm64|x64] [--ffmpeg /path/to/ffmpeg]');
    exit(64);
  }
  final arch = opt('arch') ?? (platform == 'macos' ? 'universal' : 'x64');
  final out = Directory(p.join('third_party', platform!, 'bin'));
  if (await out.exists()) await out.delete(recursive: true);
  await out.create(recursive: true);
  final work = await Directory.systemTemp.createTemp('finder-deps');
  final installer = BinaryInstaller();
  void progress(double? f, String stage) =>
      stdout.write('\r  $stage ${f == null ? '' : '${(f * 100).toStringAsFixed(0)}%'}      ');

  try {
    // yt-dlp (onedir build; the macOS one is universal2)
    final (asset, folder) = switch (platform) {
      'macos' => (DependencySources.ytDlpMacAsset, DependencySources.ytDlpMacFolder),
      'linux' => (
          arch == 'arm64' ? DependencySources.ytDlpLinuxArm64Asset : DependencySources.ytDlpLinuxX64Asset,
          DependencySources.ytDlpLinuxFolder,
        ),
      _ => (
          arch == 'arm64' ? DependencySources.ytDlpWindowsArm64Asset : DependencySources.ytDlpWindowsX64Asset,
          DependencySources.ytDlpWindowsFolder,
        ),
    };
    stdout.writeln('yt-dlp: $asset');
    final ytZip = await installer.installAsset(
      releaseBase: DependencySources.ytDlpReleaseBase,
      checksumsUrl: Uri.parse(DependencySources.ytDlpChecksums),
      assetName: asset,
      target: File(p.join(work.path, asset)),
      onProgress: progress,
    );
    stdout.writeln('\n  verified (SHA-256)');
    await BinaryInstaller.extractZip(ytZip, Directory(p.join(out.path, folder)));
    if (platform == 'linux') {
      final exe = arch == 'arm64'
          ? DependencySources.ytDlpLinuxArm64Executable
          : DependencySources.ytDlpLinuxX64Executable;
      final path = p.join(out.path, folder, exe);
      if (!File(path).existsSync()) throw StateError('yt-dlp archive had an unexpected layout');
      await _run('chmod', ['755', path]);
    }

    // FFmpeg
    if (platform == 'linux') {
      final ffAsset = arch == 'arm64'
          ? DependencySources.ffmpegLinuxArm64Asset
          : DependencySources.ffmpegLinuxX64Asset;
      stdout.writeln('ffmpeg: $ffAsset');
      final archive = await installer.installAsset(
        releaseBase: DependencySources.ffmpegReleaseBase,
        checksumsUrl: Uri.parse(DependencySources.ffmpegChecksums),
        assetName: ffAsset,
        target: File(p.join(work.path, ffAsset)),
        onProgress: progress,
      );
      stdout.writeln('\n  verified (SHA-256)');
      final x = Directory(p.join(work.path, 'ffmpeg'));
      await BinaryInstaller.extractTarXz(archive, x);
      final files = await x.list(recursive: true).where((e) => e is File).cast<File>().toList();
      File find(String n) => files.firstWhere((f) => p.basename(f.path).toLowerCase() == n);
      for (final tool in ['ffmpeg', 'ffprobe']) {
        final dest = p.join(out.path, tool);
        await find(tool).copy(dest);
        await _run('chmod', ['755', dest]);
      }
      await find('license.txt').copy(p.join(out.path, 'FFMPEG-LICENSE.txt'));
    } else if (platform == 'windows') {
      final ffAsset = arch == 'arm64'
          ? DependencySources.ffmpegWindowsArm64Asset
          : DependencySources.ffmpegWindowsX64Asset;
      stdout.writeln('ffmpeg: $ffAsset');
      final zip = await installer.installAsset(
        releaseBase: DependencySources.ffmpegReleaseBase,
        checksumsUrl: Uri.parse(DependencySources.ffmpegChecksums),
        assetName: ffAsset,
        target: File(p.join(work.path, ffAsset)),
        onProgress: progress,
      );
      stdout.writeln('\n  verified (SHA-256)');
      final x = Directory(p.join(work.path, 'ffmpeg'));
      await BinaryInstaller.extractZip(zip, x);
      final files = await x.list(recursive: true).where((e) => e is File).cast<File>().toList();
      File find(String n) => files.firstWhere((f) => p.basename(f.path).toLowerCase() == n);
      await find('ffmpeg.exe').copy(p.join(out.path, 'ffmpeg.exe'));
      await find('ffprobe.exe').copy(p.join(out.path, 'ffprobe.exe'));
      await find('license.txt').copy(p.join(out.path, 'FFMPEG-LICENSE.txt'));
    } else {
      final ff = opt('ffmpeg');
      if (ff != null) {
        // Bring-your-own build (must be self-contained, not a Homebrew build
        // linked against /opt/homebrew libraries).
        final probe = p.join(p.dirname(ff), 'ffprobe');
        for (final src in [ff, probe]) {
          if (!File(src).existsSync()) throw StateError('missing $src');
          await File(src).copy(p.join(out.path, p.basename(src)));
        }
        stdout.writeln('ffmpeg: copied from ${p.dirname(ff)}');
      } else {
        final arches = switch (arch) {
          'arm64' => ['arm64'],
          'x64' => ['amd64'],
          _ => ['arm64', 'amd64'],
        };
        for (final tool in ['ffmpeg', 'ffprobe']) {
          final slices = <String>[];
          for (final a in arches) {
            stdout.writeln('$tool: macOS $a');
            final zip = await _downloadMacFfmpeg(installer, tool, a, work, progress);
            stdout.writeln('\n  verified (SHA-256)');
            final x = Directory(p.join(work.path, '$tool-$a'));
            await BinaryInstaller.extractZip(zip, x);
            final bin = File(p.join(x.path, tool));
            if (!await bin.exists()) throw StateError('$tool archive had an unexpected layout');
            slices.add(bin.path);
          }
          final dest = p.join(out.path, tool);
          if (slices.length == 1) {
            await File(slices.single).copy(dest);
          } else {
            await _run('/usr/bin/lipo', ['-create', ...slices, '-output', dest]);
          }
        }
      }
      for (final tool in ['ffmpeg', 'ffprobe']) {
        final path = p.join(out.path, tool);
        await _run('/bin/chmod', ['755', path]);
        // Refuse builds that depend on libraries outside the app bundle.
        final libs = await Process.run('/usr/bin/otool', ['-L', path]);
        final external = (libs.stdout as String)
            .split('\n')
            .skip(1)
            .map((l) => l.trim())
            // Universal binaries print an "<file> (architecture …):" header
            // per slice; only the library lines matter.
            .where((l) => l.isNotEmpty && !l.endsWith(':'))
            .where((l) => !l.startsWith('/usr/lib/') && !l.startsWith('/System/'))
            .toList();
        if (external.isNotEmpty) {
          throw StateError('$tool links to libraries outside macOS and would not run on other Macs:\n'
              '${external.join('\n')}');
        }
      }
    }
    stdout.writeln('Done → ${out.path}');
  } finally {
    await work.delete(recursive: true);
  }
}

/// Resolves the "latest release" redirect, then downloads the zip and checks it
/// against the `.sha256` published next to it.
Future<File> _downloadMacFfmpeg(
  BinaryInstaller installer,
  String tool,
  String arch,
  Directory work,
  InstallProgress progress,
) async {
  final client = HttpClient();
  final Uri resolved;
  try {
    final redirect = Uri.parse('${DependencySources.ffmpegMacRedirectBase}/$arch/release/$tool.zip');
    final req = await client.getUrl(redirect)..followRedirects = false;
    final res = await req.close();
    await res.drain<void>();
    final location = res.headers.value(HttpHeaders.locationHeader);
    if (location == null) throw StateError('no release redirect for $tool/$arch (HTTP ${res.statusCode})');
    resolved = redirect.resolve(location);
  } finally {
    client.close(force: true);
  }
  final base = resolved.toString().substring(0, resolved.toString().lastIndexOf('/'));
  stdout.writeln('  ${resolved.pathSegments.reversed.skip(1).first}');
  return installer.installAsset(
    releaseBase: base,
    checksumsUrl: Uri.parse('$resolved.sha256'),
    assetName: '$tool.zip',
    target: File(p.join(work.path, '$tool-$arch.zip')),
    onProgress: progress,
  );
}

Future<void> _run(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) throw StateError('$exe failed: ${r.stderr}');
}
