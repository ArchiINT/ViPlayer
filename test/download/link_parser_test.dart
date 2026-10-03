import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/download/link_parser.dart';

void main() {
  void expectLink(
    String input,
    MusicService service,
    LinkKind kind,
    String id,
  ) {
    final link = LinkParser.parse(input);
    expect(link, isNotNull, reason: input);
    expect(
      (link!.service, link.kind, link.id),
      (service, kind, id),
      reason: input,
    );
  }

  test('YouTube and YouTube Music', () {
    const id = 'vg95MYlTb3c';
    for (final url in [
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&list=RDxyz&t=42',
      'https://m.youtube.com/watch?v=$id',
      'https://music.youtube.com/watch?v=$id&si=tracking',
      'https://youtu.be/$id?si=abc',
      'youtu.be/$id',
      'https://www.youtube.com/shorts/$id',
      '  https://youtu.be/$id  ',
    ]) {
      expectLink(url, MusicService.youtube, LinkKind.track, id);
    }
    expectLink(
      'https://music.youtube.com/playlist?list=OLAK5uy_abc123',
      MusicService.youtube,
      LinkKind.album,
      'OLAK5uy_abc123',
    );
    expectLink(
      'https://www.youtube.com/playlist?list=PLxyz',
      MusicService.youtube,
      LinkKind.playlist,
      'PLxyz',
    );
  });

  test('SoundCloud', () {
    expectLink(
      'https://soundcloud.com/nocopyrightsounds/angelrot-backtoback-ncs?in=x',
      MusicService.soundcloud,
      LinkKind.track,
      'nocopyrightsounds/angelrot-backtoback-ncs',
    );
    expectLink(
      'https://m.soundcloud.com/ncs/sets/best-of-2025',
      MusicService.soundcloud,
      LinkKind.playlist,
      'ncs/sets/best-of-2025',
    );
    expectLink(
      'https://on.soundcloud.com/AbC123',
      MusicService.soundcloud,
      LinkKind.track,
      'on.soundcloud.com/AbC123',
    );
  });

  test('Spotify', () {
    const id = '4uLU6hMCjMI75M1A2tKUQC';
    expectLink(
      'https://open.spotify.com/track/$id?si=123',
      MusicService.spotify,
      LinkKind.track,
      id,
    );
    expectLink(
      'https://open.spotify.com/intl-de/album/$id',
      MusicService.spotify,
      LinkKind.album,
      id,
    );
    expectLink(
      'spotify:playlist:$id',
      MusicService.spotify,
      LinkKind.playlist,
      id,
    );
  });

  test('rejects everything else', () {
    for (final input in [
      '',
      'hello world',
      'https://example.com/watch?v=vg95MYlTb3c',
      'https://www.youtube.com/@channel',
      'https://youtu.be/short',
      'https://soundcloud.com/just-a-user',
      'https://soundcloud.com/discover/sets',
      'https://open.spotify.com/artist/4uLU6hMCjMI75M1A2tKUQC',
      'https://open.spotify.com/track/tooShort',
    ]) {
      expect(LinkParser.parse(input), isNull, reason: input);
    }
  });
}
