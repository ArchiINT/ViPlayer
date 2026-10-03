import 'package:flutter/foundation.dart';

import 'download_models.dart';

enum LinkKind { track, album, playlist }

/// A recognised music link.
@immutable
class ParsedLink {
  const ParsedLink(this.service, this.kind, this.id, this.url);

  final MusicService service;
  final LinkKind kind;

  /// Service id (video id, playlist id, Spotify id). For SoundCloud — which
  /// has no ids in its URLs — the canonical URL path.
  final String id;

  /// Normalised URL.
  final String url;

  @override
  bool operator ==(Object other) =>
      other is ParsedLink &&
      other.service == service &&
      other.kind == kind &&
      other.id == id;

  @override
  int get hashCode => Object.hash(service, kind, id);

  @override
  String toString() => 'ParsedLink($service, $kind, $id)';
}

/// Recognises YouTube / YouTube Music, SoundCloud and Spotify links, with the
/// usual variations (short links, mobile hosts, tracking parameters).
/// Returns null for anything else.
abstract final class LinkParser {
  static final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');

  static ParsedLink? parse(String input) {
    final text = input.trim();
    final spotifyUri = RegExp(
      r'^spotify:(track|album|playlist):([A-Za-z0-9]{22})$',
    ).firstMatch(text);
    if (spotifyUri != null) {
      return _spotify(spotifyUri.group(1)!, spotifyUri.group(2)!);
    }

    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    switch (host) {
      case 'youtube.com' || 'music.youtube.com':
        return _youtube(uri, segments);
      case 'youtu.be':
        return segments.isEmpty ? null : _youtubeVideo(segments.first);
      case 'soundcloud.com':
        return _soundcloud(segments);
      case 'on.soundcloud.com':
        // Short link: resolved by following the redirect (SoundCloudClient).
        return segments.isEmpty
            ? null
            : ParsedLink(
                MusicService.soundcloud,
                LinkKind.track,
                'on.soundcloud.com/${segments.first}',
                'https://on.soundcloud.com/${segments.first}',
              );
      case 'open.spotify.com':
        // Locale prefix: open.spotify.com/intl-de/track/...
        final s = segments.isNotEmpty && segments.first.startsWith('intl-')
            ? segments.sublist(1)
            : segments;
        if (s.length < 2) return null;
        return _spotify(s[0], s[1]);
    }
    return null;
  }

  static ParsedLink? _youtube(Uri uri, List<String> segments) {
    final videoId = uri.queryParameters['v'];
    if (segments.firstOrNull == 'watch' && videoId != null) {
      return _youtubeVideo(videoId);
    }
    if (segments.length >= 2 &&
        (segments[0] == 'shorts' || segments[0] == 'live')) {
      return _youtubeVideo(segments[1]);
    }
    final list = uri.queryParameters['list'];
    if (segments.firstOrNull == 'playlist' && list != null) {
      // YouTube Music albums are playlists whose id starts with OLAK5uy_.
      final kind = list.startsWith('OLAK5uy_')
          ? LinkKind.album
          : LinkKind.playlist;
      return ParsedLink(
        MusicService.youtube,
        kind,
        list,
        'https://www.youtube.com/playlist?list=$list',
      );
    }
    return null;
  }

  static ParsedLink? _youtubeVideo(String id) => _youtubeId.hasMatch(id)
      ? ParsedLink(
          MusicService.youtube,
          LinkKind.track,
          id,
          'https://www.youtube.com/watch?v=$id',
        )
      : null;

  static ParsedLink? _soundcloud(List<String> segments) {
    if (segments.length < 2) return null; // a user page, not a track
    const reserved = {'discover', 'search', 'you', 'stream', 'upload'};
    if (reserved.contains(segments[0])) return null;
    final isSet = segments[1] == 'sets' && segments.length >= 3;
    final path = (isSet ? segments.take(3) : segments.take(2)).join('/');
    return ParsedLink(
      MusicService.soundcloud,
      isSet ? LinkKind.playlist : LinkKind.track,
      path,
      'https://soundcloud.com/$path',
    );
  }

  static ParsedLink? _spotify(String type, String id) {
    final kind = switch (type) {
      'track' => LinkKind.track,
      'album' => LinkKind.album,
      'playlist' => LinkKind.playlist,
      _ => null,
    };
    if (kind == null || !_spotifyId.hasMatch(id)) return null;
    return ParsedLink(
      MusicService.spotify,
      kind,
      id,
      'https://open.spotify.com/$type/$id',
    );
  }
}
