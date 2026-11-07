import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes an executable POSIX shell script and returns its path.
Future<String> writeScript(Directory dir, String name, String body, {bool executable = true}) async {
  final file = File(p.join(dir.path, name));
  await file.writeAsString('#!/bin/sh\n$body\n');
  if (executable) {
    await Process.run('chmod', ['755', file.path]);
  }
  return file.path;
}

/// A fake yt-dlp. Behaviour depends on the URL (always the last argument):
///
/// * `--version`                → prints a version
/// * `.../ok`                   → realistic progress, creates file, exit 0
/// * `.../private`              → yt-dlp style private-video error, exit 1
/// * `.../slow`                 → spawns a child `sleep`, waits (for cancellation tests)
/// * `.../meta-playlist`        → prints playlist JSON
/// * `.../meta-video`           → prints video JSON
const fakeYtDlpScript = r'''
for last in "$@"; do :; done
if [ "$1" = "--ignore-config" ] && [ "$2" = "--version" ]; then echo "2026.10.26"; exit 0; fi
dir=""; prev=""
for a in "$@"; do
  if [ "$prev" = "-P" ]; then dir="${a#home:}"; fi
  prev="$a"
done
case "$last" in
  */ok)
    out="$dir/Fake Video [ok1].mp4"
    echo "[cg]dest|$out"
    echo "[cg]dl|downloading|0|1000|NA|NA|NA|NA|NA|137"
    echo "[cg]dl|downloading|500|1000|NA|250.0|2|NA|NA|137"
    echo "[cg]dl|finished|1000|1000|NA|NA|NA|NA|NA|137"
    echo "[cg]dl|downloading|100|200|NA|100.0|1|NA|NA|140"
    echo "[cg]dl|finished|200|200|NA|NA|NA|NA|NA|140"
    echo "WARNING: harmless warning" 1>&2
    echo "[cg]pp|started|Merger"
    printf 'media' > "$out"
    echo "[cg]pp|finished|Merger"
    echo "[cg]meta|720|1280|mp4"
    echo "[cg]file|$out"
    exit 0;;
  */private)
    echo "ERROR: [youtube] abc: Private video. Sign in if you've been granted access to this video" 1>&2
    exit 1;;
  */slow)
    echo "[cg]dest|$dir/Slow [s].mp4"
    printf 'x' > "$dir/Slow [s].f137.mp4.part"
    echo "[cg]dl|downloading|1|100|NA|1.0|99|NA|NA|137"
    sleep 30 &
    echo "child:$!" 1>&2
    wait;;
  */meta-null)
    echo "null"
    echo "ERROR: [youtube] x: Video unavailable" 1>&2
    exit 1;;
  */meta-playlist)
    echo '{"_type":"playlist","id":"PL","title":"Fake Course","channel":"Me","entries":[{"id":"e1","title":"One","url":"https://fake.test/e1","duration":10},{"id":"e2","title":"[Private video]","url":"https://fake.test/e2"}]}'
    exit 0;;
  */meta-video)
    echo '{"id":"v","title":"Solo","webpage_url":"https://fake.test/v","duration":5,"formats":[{"format_id":"18","ext":"mp4","width":640,"height":360,"vcodec":"avc1","acodec":"mp4a"}]}'
    exit 0;;
  *)
    echo "ERROR: Unsupported URL: $last" 1>&2
    exit 1;;
esac
''';

const fakeFfmpegScript = r'''
echo "ffmpeg version 7.1.1 Copyright (c) 2000-2025 the FFmpeg developers"
exit 0
''';
