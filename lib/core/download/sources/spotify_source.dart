import 'dart:convert';

import 'package:http/http.dart' as http;

import '../download_models.dart';
import '../http_download.dart';
import '../link_parser.dart';

/// Spotify metadata (no audio — Spotify streams are DRM-protected; the
/// audio comes from YouTube, see docs/DOWNLOADS.md).
///
/// Reads the public embed pages (no account, no API key). They carry title,
/// artists, duration and artwork; albums also their name and release date.
/// Playlist embeds list a limited number of tracks (Spotify decides how many).
class SpotifySource {
  SpotifySource(this._http);

  final http.Client _http;

  static String trackUrl(String id) => 'https://open.spotify.com/track/$id';

  Future<ResolvedLink> resolve(ParsedLink link) async {
    final type = switch (link.kind) {
      LinkKind.track => 'track',
      LinkKind.album => 'album',
      LinkKind.playlist => 'playlist',
    };
    final entity = await _entity(type, link.id);

    if (link.kind == LinkKind.track) {
      return ResolvedLink(
        service: MusicService.spotify,
        items: [
          DownloadCandidate(
            service: MusicService.spotify,
            sourceId: link.id,
            sourceUrl: trackUrl(link.id),
            title: entity['name'] as String? ?? entity['title']! as String,
            artist: _artists(entity),
            durationMs: (entity['duration'] as num?)?.toInt() ?? 0,
            coverUrl: _largestImage(entity),
            year: _year(entity),
          ),
        ],
      );
    }

    final isAlbum = link.kind == LinkKind.album;
    final name = entity['name'] as String? ?? entity['title']! as String;
    final cover = _largestImage(entity);
    final tracks = (entity['trackList'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    return ResolvedLink(
      service: MusicService.spotify,
      collectionTitle: name,
      collectionCoverUrl: cover,
      items: [
        for (final (i, t) in tracks.indexed)
          if (_trackId(t) case final id?)
            DownloadCandidate(
              service: MusicService.spotify,
              sourceId: id,
              sourceUrl: trackUrl(id),
              title: t['title']! as String,
              artist: t['subtitle'] as String? ?? '',
              durationMs: (t['duration'] as num?)?.toInt() ?? 0,
              // Playlist entries carry no artwork; looked up per track
              // before download (coverFor).
              coverUrl: isAlbum ? cover : null,
              album: isAlbum ? name : null,
              year: isAlbum ? _year(entity) : null,
              trackNumber: isAlbum ? i + 1 : null,
            ),
      ],
    );
  }

  /// Artwork of a single track (for playlist entries).
  Future<String?> coverFor(String trackId) async =>
      _largestImage(await _entity('track', trackId));

  Future<Map<String, Object?>> _entity(String type, String id) async {
    final html = await fetchText(
      _http,
      Uri.parse('https://open.spotify.com/embed/$type/$id'),
    );
    final json = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html)?.group(1);
    if (json == null) {
      throw const DownloadException(
        DownloadFailure.failed,
        'Spotify changed its page; update ViPlayer',
      );
    }
    try {
      final data = jsonDecode(json) as Map<String, Object?>;
      final entity =
          (((data['props'] as Map)['pageProps'] as Map)['state'] as Map)['data']
              as Map;
      return (entity['entity'] as Map).cast<String, Object?>();
    } on Object {
      throw const DownloadException(DownloadFailure.notFound);
    }
  }

  static String? _trackId(Map<String, Object?> t) {
    final uri = t['uri'] as String?;
    return uri?.startsWith('spotify:track:') == true
        ? uri!.split(':').last
        : null;
  }

  static String _artists(Map<String, Object?> e) {
    final artists = (e['artists'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map((a) => a['name'] as String?)
        .nonNulls
        .toList();
    return artists.isNotEmpty
        ? artists.join(', ')
        : e['subtitle'] as String? ?? '';
  }

  static int? _year(Map<String, Object?> e) {
    final release = e['releaseDate'] as Map<String, Object?>?;
    return DateTime.tryParse(release?['isoString'] as String? ?? '')?.year;
  }

  /// Largest image among the entity's artwork lists.
  static String? _largestImage(Map<String, Object?> e) {
    final candidates = <Map<String, Object?>>[
      ...((e['visualIdentity'] as Map<String, Object?>?)?['image']
                  as List<Object?>? ??
              const [])
          .cast<Map<String, Object?>>(),
      ...((e['coverArt'] as Map<String, Object?>?)?['sources']
                  as List<Object?>? ??
              const [])
          .cast<Map<String, Object?>>(),
    ];
    if (candidates.isEmpty) return null;
    int size(Map<String, Object?> m) =>
        ((m['maxWidth'] ?? m['width']) as num?)?.toInt() ?? 0;
    candidates.sort((a, b) => size(b).compareTo(size(a)));
    return candidates.first['url'] as String?;
  }
}
