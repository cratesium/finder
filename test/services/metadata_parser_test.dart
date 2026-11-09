import 'dart:convert';

import 'package:finder/core/errors/app_error.dart';
import 'package:finder/models/download_options.dart';
import 'package:finder/models/media_info.dart';
import 'package:finder/services/ytdlp/metadata_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> fmt(String id, {int? w, int? h, String v = 'avc1', String a = 'none', String ext = 'mp4'}) => {
      'format_id': id,
      'ext': ext,
      'width': w,
      'height': h,
      'vcodec': v,
      'acodec': a,
    };

void main() {
  group('MetadataParser – playlists', () {
    final playlistJson = {
      '_type': 'playlist',
      'id': 'PL1',
      'title': 'Course: Flutter',
      'channel': 'Teacher',
      'extractor_key': 'YoutubeTab',
      'webpage_url': 'https://www.youtube.com/playlist?list=PL1',
      'playlist_count': 5,
      'entries': [
        {
          '_type': 'url',
          'ie_key': 'Youtube',
          'id': 'a1',
          'url': 'https://www.youtube.com/watch?v=a1',
          'title': 'Intro',
          'duration': 61.5,
          'thumbnails': [
            {'url': 'https://i.ytimg.com/a1/small.jpg', 'width': 120},
            {'url': 'https://i.ytimg.com/a1/mid.jpg', 'width': 480},
            {'url': 'https://i.ytimg.com/a1/big.jpg', 'width': 1280},
          ],
        },
        {
          '_type': 'url',
          'ie_key': 'Youtube',
          'id': 'p2',
          'url': 'https://www.youtube.com/watch?v=p2',
          'title': '[Private video]',
          'duration': null,
        },
        {
          '_type': 'url',
          'ie_key': 'Youtube',
          'id': 'd3',
          'url': 'https://www.youtube.com/watch?v=d3',
          'title': '[Deleted video]',
        },
        {
          '_type': 'url',
          'ie_key': 'Youtube',
          'id': 'm4',
          'url': 'https://www.youtube.com/watch?v=m4',
          'title': 'Members',
          'availability': 'subscriber_only',
          'duration': 100,
        },
        null,
      ],
    };

    test('parses playlist information and entries', () {
      final info = MetadataParser.parse(playlistJson, sourceUrl: 'x');
      expect(info.kind, MediaKind.playlist);
      expect(info.title, 'Course: Flutter');
      expect(info.uploader, 'Teacher');
      expect(info.totalCount, 5);
      expect(info.entries.first.id, 'a1');
      expect(info.entries.first.playlistIndex, 1);
      expect(info.entries.first.extractor, 'Youtube');
      expect(info.entries.first.duration, const Duration(milliseconds: 61500));
      expect(info.entries.first.thumbnailUrl, 'https://i.ytimg.com/a1/mid.jpg');
      expect(info.thumbnailUrl, 'https://i.ytimg.com/a1/mid.jpg');
    });

    test('handles partially unavailable playlists', () {
      final info = MetadataParser.parse(playlistJson, sourceUrl: 'x');
      expect(info.entries[1].availability, EntryAvailability.private);
      expect(info.entries[2].availability, EntryAvailability.unavailable);
      expect(info.entries[3].availability, EntryAvailability.needsAuth);
      expect(info.entries[4].availability, EntryAvailability.unavailable);
      expect(info.downloadableCount, 1);
      expect(info.unavailableCount, 4);
    });

    test('total duration sums known durations only', () {
      final info = MetadataParser.parse(playlistJson, sourceUrl: 'x');
      expect(info.totalDuration, const Duration(milliseconds: 161500));
      expect(info.entriesWithoutDuration, 3);
    });

    test('nested playlists are flagged', () {
      final info = MetadataParser.parse({
        '_type': 'playlist',
        'id': 'ch',
        'title': 'Channel',
        'entries': [
          {'_type': 'url', 'ie_key': 'YoutubeTab', 'id': 'UU1', 'url': 'https://youtube.com/playlist?list=UU1', 'title': 'Videos'},
        ],
      }, sourceUrl: 'x');
      expect(info.entries.single.availability, EntryAvailability.nestedPlaylist);
    });
  });

  group('MetadataParser – single video', () {
    final videoJson = {
      'id': 'v1',
      'title': 'Lesson 1',
      'webpage_url': 'https://www.youtube.com/watch?v=v1',
      'extractor_key': 'Youtube',
      'uploader': 'Teacher',
      'duration': 600,
      'thumbnail': 'https://i.ytimg.com/v1.jpg',
      'formats': [
        fmt('sb0', ext: 'mhtml', v: 'none'),
        fmt('140', a: 'mp4a.40.2', v: 'none', ext: 'm4a'),
        fmt('134', w: 640, h: 360),
        fmt('136', w: 1280, h: 720),
        fmt('137', w: 1920, h: 1080),
        {...fmt('drm', w: 3840, h: 2160), 'has_drm': true},
      ],
    };

    test('parses formats and resolutions', () {
      final info = MetadataParser.parse(videoJson, sourceUrl: 'x');
      expect(info.kind, MediaKind.video);
      final e = info.entries.single;
      expect(e.formats.map((f) => f.formatId), ['140', '134', '136', '137']);
      expect(e.maxResolution, 1080);
      expect(e.hasAudioStreams, isTrue);
      expect(e.availableQualities, {
        VideoQuality.best,
        VideoQuality.p1080,
        VideoQuality.p720,
        VideoQuality.p360,
      });
    });

    test('vertical videos are bucketed by their short side', () {
      final info = MetadataParser.parse({
        'id': 'short',
        'title': 'Short',
        'formats': [fmt('1', w: 1080, h: 1920)],
      }, sourceUrl: 'x');
      expect(info.entries.single.availableQualities, {VideoQuality.best, VideoQuality.p1080});
    });

    test('DRM-only content raises a DRM error', () {
      expect(
        () => MetadataParser.parse({
          'id': 'x',
          'title': 'x',
          'formats': [
            {...fmt('1', w: 1920, h: 1080), 'has_drm': true},
          ],
        }, sourceUrl: 'x'),
        throwsA(isA<AppError>().having((e) => e.kind, 'kind', AppErrorKind.drmProtected)),
      );
    });

    test('live streams are flagged', () {
      final info = MetadataParser.parse({'id': 'l', 'title': 'Live', 'is_live': true, 'webpage_url': 'https://x.com/l'}, sourceUrl: 'x');
      expect(info.entries.single.availability, EntryAvailability.live);
    });

    test('invalid JSON is a friendly error', () {
      expect(() => MetadataParser.parseJson('not json', sourceUrl: 'x'), throwsA(isA<AppError>()));
      expect(() => MetadataParser.parseJson(jsonEncode([1, 2]), sourceUrl: 'x'), throwsA(isA<AppError>()));
    });
  });
}
