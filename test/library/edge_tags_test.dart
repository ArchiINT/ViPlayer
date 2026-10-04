import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/library/audio_files.dart';
import 'package:viplayer/core/library/mp4_tags.dart';

/// Real-world files that broke tag reading (found on a user's phone).
void main() {
  late Directory covers;
  setUp(() => covers = Directory.systemTemp.createTempSync('vp_edge_'));
  tearDown(() => covers.deleteSync(recursive: true));

  ScannedFile scan(String path) {
    final stat = File(path).statSync();
    return readAudioFiles([
      FoundFile(path: path, sizeBytes: stat.size, modifiedMs: 0),
    ], covers.path).single;
  }

  const ytBot = 'test/fixtures/edge/ytbot_date.m4a';

  test(
    'the tag library rejects yt-dlp style dates (why the fallback exists)',
    () {
      expect(() => readMetadata(File(ytBot)), throwsA(anything));
    },
  );

  test('MP4 fallback reads every tag, the date and the cover', () {
    final tags = Mp4Tags.read(File(ytBot))!;
    expect(tags.title, 'Троллейбус 54 - сияние (Official Music Video)');
    expect(tags.artist, 'Троллейбус 54');
    expect(tags.album, 'Альбом');
    expect(tags.year, 2017);
    expect(tags.trackNumber, 5);
    expect(tags.cover, isNotEmpty);
    expect(tags.duration!.inMilliseconds, closeTo(3000, 100));
  });

  test('scanner: tidy title, all tags, cover', () {
    final s = scan(ytBot);
    expect(s.title, 'сияние', reason: 'artist prefix and noise removed');
    expect(s.artist, 'Троллейбус 54');
    expect(s.year, 2017);
    expect(s.coverId, isNotNull);
    expect(s.durationMs, closeTo(3000, 100));
  });

  test('scanner: untagged "Artist — Title" file name', () {
    final s = scan('test/fixtures/edge/SadSvit — Двоє.mp3');
    expect(s.artist, 'SadSvit');
    expect(s.title, 'Двоє');
  });

  test('a file that is not MP4 at all does not crash the fallback', () {
    expect(Mp4Tags.read(File('test/fixtures/edge/SadSvit — Двоє.mp3')), isNull);
  });
}
