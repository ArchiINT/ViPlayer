import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viplayer/core/download/tools/tagger.dart';

/// Writes tags with each tagger and reads them back with the same reader the
/// library scanner uses.
void main() {
  late Directory temp;
  late bool hasFfmpeg;
  final cover = File('test/fixtures/audio/album/cover.jpg').readAsBytesSync();

  setUpAll(() async {
    hasFfmpeg = await FfmpegTagger.isAvailable();
  });
  setUp(() async => temp = await Directory.systemTemp.createTemp('vp_tag_'));
  tearDown(() => temp.delete(recursive: true));

  final tags = TrackTags(
    title: 'Чёрный лёд',
    artist: 'Кибер Волна',
    album: 'Москва 2077',
    year: 2024,
    trackNumber: 3,
    cover: Uint8List.fromList(cover),
  );

  Future<File> copy(String fixture, String ext) async =>
      File(fixture).copy(p.join(temp.path, 'track.$ext'));

  void expectTags(File file) {
    final m = readMetadata(file, getImage: true);
    expect(m.title, tags.title);
    expect(m.artist, tags.artist);
    expect(m.album, tags.album);
    expect(m.pictures, isNotEmpty, reason: 'cover in ${file.path}');
  }

  Future<File> makeOpus() async {
    final out = File(p.join(temp.path, 'track.opus'));
    await Process.run('ffmpeg', [
      '-v',
      'error',
      '-y',
      '-i',
      'test/fixtures/audio/album/ghost_signal.opus',
      '-map',
      '0:a',
      '-c',
      'copy',
      '-map_metadata',
      '-1',
      out.path,
    ]);
    return out;
  }

  for (final (name, fixture, ext) in [
    ('m4a', 'test/fixtures/audio/neon_rain.m4a', 'm4a'),
    ('mp3', 'test/fixtures/audio/black_ice.mp3', 'mp3'),
  ]) {
    test('ffmpeg tagger: $name', () async {
      if (!hasFfmpeg) return markTestSkipped('ffmpeg not installed');
      final file = await copy(fixture, ext);
      await const FfmpegTagger().write(file, tags);
      expectTags(file);
    });
  }

  test('ffmpeg tagger: opus (cover as METADATA_BLOCK_PICTURE)', () async {
    if (!hasFfmpeg) return markTestSkipped('ffmpeg not installed');
    final file = await makeOpus();
    await const FfmpegTagger().write(file, tags);
    expectTags(file);
  });

  test('dart tagger: mp3 (Android)', () async {
    final file = await copy('test/fixtures/audio/black_ice.mp3', 'mp3');
    await const DartTagger().write(file, tags);
    expectTags(file);
  });

  // SoundCloud often serves MP3s with no ID3 tag at all; the tag library
  // silently dropped the cover for those (found on a user's phone).
  test('dart tagger: mp3 without any ID3 tag gets tags and cover', () async {
    final file = await copy('test/fixtures/edge/raw_no_id3.mp3', 'mp3');
    expect(String.fromCharCodes(file.readAsBytesSync().take(3)), isNot('ID3'));
    await const DartTagger().write(file, tags);
    expectTags(file);
    expect(readMetadata(file).duration!.inMilliseconds, closeTo(2000, 300));
  });

  test('dart tagger: rewriting an mp3 replaces the old tag', () async {
    final file = await copy('test/fixtures/audio/black_ice.mp3', 'mp3');
    await const DartTagger().write(file, tags);
    await const DartTagger().write(
      file,
      TrackTags(title: 'Second', artist: 'Again', cover: tags.cover),
    );
    final m = readMetadata(file, getImage: true);
    expect(m.title, 'Second');
    expect(m.pictures, hasLength(1));
  });
}
