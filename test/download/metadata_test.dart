import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/download/metadata_cleanup.dart';
import 'package:viplayer/core/download/track_matcher.dart';

DownloadCandidate _yt(String title, String artist, int seconds) =>
    DownloadCandidate(
      service: MusicService.youtube,
      sourceId: title,
      sourceUrl: '',
      title: title,
      artist: artist,
      durationMs: seconds * 1000,
    );

void main() {
  group('MetadataCleanup', () {
    test('splits "Artist - Title" and strips upload noise', () {
      expect(
        MetadataCleanup.fromUpload(
          title: 'Alan Walker - Fade [NCS Release] (Official Video)',
          uploader: 'NoCopyrightSounds',
        ),
        (artist: 'Alan Walker', title: 'Fade'),
      );
      expect(
        MetadataCleanup.fromUpload(
          title: 'angelrot - backtoback [NCS Release]',
          uploader: 'NCS',
        ),
        (artist: 'angelrot', title: 'backtoback'),
      );
    });

    test('keeps meaningful brackets', () {
      expect(
        MetadataCleanup.stripNoise('Song (feat. Someone) [Remix] (Lyrics)'),
        'Song (feat. Someone) [Remix]',
      );
      expect(
        MetadataCleanup.stripNoise('Song (Live at Wembley) [4K]'),
        'Song (Live at Wembley)',
      );
    });

    test('site watermarks are noise', () {
      expect(
        MetadataCleanup.stripNoise('The Perfect Girl [mp3uk.net]'),
        'The Perfect Girl',
      );
      expect(MetadataCleanup.stripNoise('Song (muzofond.fm)'), 'Song');
    });

    test('Topic channels give the artist', () {
      expect(
        MetadataCleanup.fromUpload(
          title: 'Fade',
          uploader: 'Alan Walker - Topic',
        ),
        (artist: 'Alan Walker', title: 'Fade'),
      );
    });

    test('no separator: uploader is the artist', () {
      expect(
        MetadataCleanup.fromUpload(
          title: 'Кукушка (Official Audio)',
          uploader: 'KinoVEVO',
        ),
        (artist: 'Kino', title: 'Кукушка'),
      );
    });
  });

  group('TrackMatcher', () {
    const wanted = DownloadCandidate(
      service: MusicService.spotify,
      sourceId: 'x',
      sourceUrl: '',
      title: 'Fade',
      artist: 'Alan Walker',
      durationMs: 264000,
    );

    test('prefers the right duration and avoids other versions', () {
      final results = [
        _yt('Alan Walker - Fade (Live)', 'Alan Walker', 265),
        _yt('Alan Walker - Fade (Sped Up)', 'Fan uploads', 200),
        _yt('Fade', 'Alan Walker - Topic', 264),
        _yt('Alan Walker - Faded', 'Alan Walker', 213),
      ];
      expect(TrackMatcher.best(wanted, results)!.title, 'Fade');
    });

    test('returns nothing when no result is the song', () {
      final results = [
        _yt('Completely different song', 'Someone', 120),
        _yt('Fade tutorial', 'Guitar Lessons', 900),
      ];
      expect(TrackMatcher.best(wanted, results), isNull);
    });

    test('a wanted remix may match a remix', () {
      const remix = DownloadCandidate(
        service: MusicService.spotify,
        sourceId: 'r',
        sourceUrl: '',
        title: 'Fade - Remix',
        artist: 'Alan Walker',
        durationMs: 200000,
      );
      final results = [
        _yt('Alan Walker - Fade', 'Alan Walker', 264),
        _yt('Alan Walker - Fade (Remix)', 'Alan Walker', 201),
      ];
      expect(TrackMatcher.best(remix, results)!.title, contains('Remix'));
    });
  });
}
