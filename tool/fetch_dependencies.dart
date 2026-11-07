// Downloads official, checksum-verified dependency builds for bundling into a
// release package. Nothing is downloaded at build time without verification.
//
//   dart run tool/fetch_dependencies.dart --platform windows [--arch x64|arm64]
//   dart run tool/fetch_dependencies.dart --platform macos [--ffmpeg /path/to/ffmpeg]
//
// Output: third_party/<platform>/bin/
//   windows: yt-dlp/yt-dlp.exe (+ _internal), ffmpeg.exe, ffprobe.exe, FFMPEG-LICENSE.txt
//   macos:   yt-dlp_macos/yt-dlp_macos (+ _internal), and ffmpeg/ffprobe if --ffmpeg is given
//
// FFmpeg has no official macOS binary with published checksums, so for macOS
// you must supply a build you trust with --ffmpeg (ffprobe must sit next to it).
import 'dart:io';

import 'package:coursegrab/core/config/app_config.dart';
import 'package:coursegrab/services/binary_installer.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final platform = opt('platform');
  final arch = opt('arch') ?? 'x64';
  if (platform != 'windows' && platform != 'macos') {
    stderr.writeln('usage: dart run tool/fetch_dependencies.dart --platform windows|macos '
        '[--arch x64|arm64] [--ffmpeg /path/to/ffmpeg]');
    exit(64);
  }
  final out = Directory(p.join('third_party', platform!, 'bin'));
  if (await out.exists()) await out.delete(recursive: true);
  await out.create(recursive: true);
  final work = await Directory.systemTemp.createTemp('coursegrab-deps');
  final installer = BinaryInstaller();
  void progress(double? f, String stage) =>
      stdout.write('\r  $stage ${f == null ? '' : '${(f * 100).toStringAsFixed(0)}%'}      ');

  try {
    // yt-dlp (onedir build)
    final (asset, folder) = platform == 'macos'
        ? (DependencySources.ytDlpMacAsset, DependencySources.ytDlpMacFolder)
        : (arch == 'arm64' ? DependencySources.ytDlpWindowsArm64Asset : DependencySources.ytDlpWindowsX64Asset,
            DependencySources.ytDlpWindowsFolder);
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

    // FFmpeg
    if (platform == 'windows') {
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
      if (ff == null) {
        stdout.writeln('ffmpeg: skipped (pass --ffmpeg /path/to/ffmpeg to bundle a build you trust)');
      } else {
        final probe = p.join(p.dirname(ff), 'ffprobe');
        for (final src in [ff, probe]) {
          if (!File(src).existsSync()) throw StateError('missing $src');
          final dest = p.join(out.path, p.basename(src));
          await File(src).copy(dest);
          await Process.run('/bin/chmod', ['755', dest]);
        }
        stdout.writeln('ffmpeg: copied from ${p.dirname(ff)}');
      }
    }
    stdout.writeln('Done → ${out.path}');
  } finally {
    await work.delete(recursive: true);
  }
}
