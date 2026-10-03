@Tags(['online'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:viplayer/core/download/link_parser.dart';
import 'package:viplayer/core/download/sources/soundcloud_source.dart';
import 'package:viplayer/core/download/sources/spotify_source.dart';
import 'package:viplayer/core/download/sources/youtube_source.dart';
import 'package:viplayer/core/download/track_matcher.dart';

/// Checks the sources against the real services with free-to-use NCS
/// releases. Services change without notice — when this fails, a source
/// needs updating.
void main() {
  final client = http.Client();
  final youtube = YoutubeSource();
  final soundcloud = SoundCloudSource(client);
  final spotify = SpotifySource(client);
  late Directory temp;

  setUpAll(() async => temp = await Directory.systemTemp.createTemp('vp_dl_'));
  tearDownAll(() async {
    youtube.close();
    client.close();
    await temp.delete(recursive: true);
  });

  const timeout = Timeout(Duration(minutes: 2));

  test('YouTube: resolve and search', () async {
    final video = await youtube.video('vg95MYlTb3c');
    expect(video.artist, 'Alan Walker');
    expect(video.title, 'Fade');
    expect(video.durationMs, greaterThan(200000));

    final results = await youtube.search('Alan Walker Fade');
    expect(results, isNotEmpty);
  }, timeout: timeout);

  test('SoundCloud: resolve track and download MP3', () async {
    final link = await soundcloud.resolve(
      'https://soundcloud.com/nocopyrightsounds/angelrot-backtoback-ncs',
    );
    final track = link.items.single;
    expect(track.artist, 'angelrot');
    expect(track.title, 'backtoback');
    expect(track.coverUrl, contains('t500x500'));

    final file = File('${temp.path}/sc.mp3');
    await soundcloud.downloadAudio(track.sourceId, file);
    expect(file.lengthSync(), greaterThan(1000000));
  }, timeout: timeout);

  test('Spotify: track and album metadata, matched on YouTube', () async {
    final track = await spotify.resolve(
      LinkParser.parse(
        'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
      )!,
    );
    final wanted = track.items.single;
    expect(wanted.title, 'Never Gonna Give You Up');
    expect(wanted.artist, 'Rick Astley');
    expect(wanted.coverUrl, isNotNull);

    final match = TrackMatcher.best(
      wanted,
      await youtube.search('${wanted.artist} ${wanted.title}'),
    );
    expect(match, isNotNull);
    expect((match!.durationMs - wanted.durationMs).abs(), lessThan(10000));

    final album = await spotify.resolve(
      LinkParser.parse(
        'https://open.spotify.com/album/4LH4d3cOWNNsVw41Gqt2kv',
      )!,
    );
    expect(album.collectionTitle, 'The Dark Side of the Moon');
    expect(album.items, hasLength(10));
    expect(album.items.first.trackNumber, 1);
  }, timeout: timeout);
}
