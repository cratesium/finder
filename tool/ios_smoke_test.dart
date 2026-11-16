// Real-network check of the iOS download engine, run on the host:
//
//   dart run tool/ios_smoke_test.dart [videoUrl] [playlistUrl]
//
// Exercises exactly the code the iOS app uses (minus AVFoundation muxing,
// which only exists on Apple devices): YouTube metadata + stream manifest via
// youtube_explode_dart, the iOS stream selection, and the resumable writer
// (downloads 2 MB, stops, then resumes with a range request to 4 MB).
import 'dart:io';

import 'package:finder/models/download_options.dart';
import 'package:finder/services/ios/resumable_writer.dart';
import 'package:finder/services/ios/stream_selection.dart';
import 'package:finder/services/ios/youtube_gateway.dart';
import 'package:finder/services/ios/youtube_link.dart';

Future<void> main(List<String> args) async {
  final videoUrl = args.isNotEmpty ? args[0] : 'https://www.youtube.com/watch?v=aqz-KE-bpKQ';
  final playlistUrl = args.length > 1 ? args[1] : 'https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI';
  final gw = YoutubeExplodeGateway();
  final tmp = await Directory.systemTemp.createTemp('finder-ios-smoke');
  try {
    final id = (YoutubeLink.resolve(videoUrl, FetchScope.single) as YoutubeVideoTarget).videoId;
    final v = await gw.video(id);
    stdout.writeln('video: "${v.title}" by ${v.author}, ${v.duration}');
    final streams = await gw.streams(id);
    final usable = streams.where((s) => s.isIosCompatible).toList();
    stdout.writeln('streams: ${streams.length} total, ${usable.length} iOS-compatible; '
        'resolutions ${usable.where((s) => s.res != null).map((s) => s.res).toSet().toList()..sort()}');

    for (final q in [VideoQuality.best, VideoQuality.p720, VideoQuality.p360]) {
      final plan = StreamSelector.select(streams, DownloadOptions(destinationDir: tmp.path, quality: q));
      stdout.writeln('  ${q.name}: ${_describe(plan)}');
    }
    final audioPlan = StreamSelector.select(streams, DownloadOptions(destinationDir: tmp.path, mode: DownloadMode.audioOnly));
    stdout.writeln('  audio: ${_describe(audioPlan)}');

    final stream = (audioPlan as SinglePlan).stream;
    final part = File('${tmp.path}/sample.part');
    const firstStop = 2 * 1024 * 1024;
    final writer = ResumableWriter();
    WriteProgress? last;
    var r = await writer.write(
      partial: part,
      source: gw.open(stream),
      totalBytes: stream.size,
      resumable: gw.isResumable(stream),
      onProgress: (w) {
        last = w;
        if (w.downloaded >= firstStop) writer.stop();
      },
    );
    stdout.writeln('first run: $r, ${await part.length()} bytes on disk, speed ${last?.speed?.toStringAsFixed(0)} B/s, eta ${last?.eta}s');
    final resumeAt = await part.length();
    final writer2 = ResumableWriter();
    r = await writer2.write(
      partial: part,
      source: (start) {
        stdout.writeln('resume requested from byte $start');
        return gw.open(stream)(start);
      },
      totalBytes: stream.size,
      onProgress: (w) {
        if (w.downloaded >= resumeAt + firstStop) writer2.stop();
      },
    );
    stdout.writeln('second run: $r, ${await part.length()} bytes on disk (of ${stream.size})');

    final listId = (YoutubeLink.resolve(playlistUrl, FetchScope.playlist) as YoutubePlaylistTarget).playlistId;
    final pl = await gw.playlist(listId);
    final first = await gw.playlistVideos(listId).take(5).toList();
    stdout.writeln('playlist: "${pl.title}" (${pl.videoCount} videos); first: ${first.map((e) => e.title).join(' | ')}');
    stdout.writeln('SMOKE OK');
  } finally {
    gw.close();
    await tmp.delete(recursive: true);
  }
}

String _describe(StreamPlan? p) => switch (p) {
      null => 'nothing compatible',
      SeparatePlan(:final video, :final audio) =>
        'video itag ${video.tag} ${video.res}p ${video.videoCodec} + audio itag ${audio.tag} (mux on device)',
      SinglePlan(:final stream) => 'single itag ${stream.tag} ${stream.kind.name} ${stream.res ?? ''} .${p.extension}',
    };
