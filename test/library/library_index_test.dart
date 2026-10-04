import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/library/fingerprint.dart';
import 'package:viplayer/core/library/library_models.dart';

LibraryTrack _track(
  String id, {
  required String title,
  String artist = '',
  String album = '',
  String? albumArtist,
  int? trackNumber,
  int? year,
  int addedAt = 0,
}) => LibraryTrack(
  id: id,
  title: title,
  artist: artist,
  album: album,
  albumArtist: albumArtist,
  trackNumber: trackNumber,
  year: year,
  durationMs: 60000,
  liked: false,
  addedAt: addedAt,
  path: '/m/$id.mp3',
);

void main() {
  group('Fingerprint', () {
    test('ignores case, punctuation and spacing in any script', () {
      expect(
        Fingerprint.fromMetadata(
          artist: 'Кибер  Волна',
          title: 'Чёрный Лёд!',
          durationMs: 200000,
        ),
        Fingerprint.fromMetadata(
          artist: 'кибер волна',
          title: 'чёрный лёд',
          durationMs: 200400,
        ),
      );
    });

    test('different songs differ', () {
      final a = Fingerprint.fromMetadata(
        artist: 'A',
        title: 'Song',
        durationMs: 180000,
      );
      expect(
        a,
        isNot(
          Fingerprint.fromMetadata(
            artist: 'A',
            title: 'Song',
            durationMs: 240000,
          ),
        ),
      );
      expect(
        a,
        isNot(
          Fingerprint.fromMetadata(
            artist: 'B',
            title: 'Song',
            durationMs: 180000,
          ),
        ),
      );
    });
  });

  group('LibraryIndex', () {
    final index = LibraryIndex.build([
      _track(
        '1',
        title: 'Neon Rain',
        artist: 'Synth Rider',
        album: 'Night City',
        trackNumber: 2,
        year: 2077,
      ),
      _track(
        '2',
        title: 'Ghost Signal',
        artist: 'Synth Rider',
        album: 'night city', // same album, different case
        trackNumber: 1,
      ),
      _track(
        '3',
        title: 'Guest Verse',
        artist: 'Guest',
        album: 'Night City',
        albumArtist: 'Synth Rider', // compilation-style
        trackNumber: 3,
      ),
      _track('4', title: 'Чёрный лёд', artist: 'Кибер Волна', addedAt: 9),
    ]);

    test('search matches word prefixes across fields and scripts', () {
      expect(index.search('neo ra').map((t) => t.id), ['1']);
      expect(index.search('night'), hasLength(3)); // album name
      expect(index.search('чёрн').single.id, '4');
      expect(index.search('кибер').single.id, '4'); // artist
      expect(index.search('eon'), isEmpty); // prefixes only
      expect(index.search('   '), isEmpty);
    });

    test('sorting', () {
      expect(
        LibraryIndex.sortTracks(
          index.tracks,
          TrackSort.title,
        ).map((t) => t.title),
        ['Ghost Signal', 'Guest Verse', 'Neon Rain', 'Чёрный лёд'],
      );
      expect(
        LibraryIndex.sortTracks(index.tracks, TrackSort.recentlyAdded).first.id,
        '4',
      );
    });
  });
}
