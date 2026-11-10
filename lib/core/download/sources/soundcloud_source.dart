import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../download_models.dart';
import '../http_download.dart';
import '../metadata_cleanup.dart';

/// SoundCloud in pure Dart, through the same public API its website uses.
///
/// The API needs a `client_id`, which the website embeds in its scripts; it
/// is looked up once and refreshed if SoundCloud rotates it.
class SoundCloudSource {
  SoundCloudSource(this._http);

  final http.Client _http;
  String? _clientId;

  static const _api = 'https://api-v2.soundcloud.com';

  Future<ResolvedLink> resolve(String url) async {
    final data = await _apiObject('/resolve', {'url': await _expand(url)});
    switch (data['kind']) {
      case 'track':
        return ResolvedLink(
          service: MusicService.soundcloud,
          items: [_candidate(data)],
        );
      case 'playlist':
        final tracks = await _fullTracks(
          (data['tracks'] as List<Object?>).cast<Map<String, Object?>>(),
        );
        final isAlbum = data['is_album'] == true;
        final title = data['title'] as String;
        return ResolvedLink(
          service: MusicService.soundcloud,
          collectionTitle: title,
          collectionCoverUrl: _artwork(data),
          items: [
            for (final (i, t) in tracks.indexed)
              _candidate(
                t,
                album: isAlbum ? title : null,
                trackNumber: isAlbum ? i + 1 : null,
              ),
          ],
        );
      default:
        throw const DownloadException(DownloadFailure.unsupportedLink);
    }
  }

  /// Tracks matching [query]. Previews-only uploads (SoundCloud Go+ "snips"),
  /// blocked ones and DRM-only ones are left out: they cannot be downloaded
  /// in full.
  Future<List<DownloadCandidate>> search(String query, {int limit = 20}) async {
    final data = await _apiObject('/search/tracks', {
      'q': query,
      'limit': '$limit',
    });
    return [
      for (final t
          in (data['collection'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>())
        if (t['policy'] != 'SNIP' &&
            t['policy'] != 'BLOCK' &&
            _transcoding(t) != null)
          _candidate(t),
    ];
  }

  /// Stream of track [id] for previews: a direct MP3 or an HLS playlist
  /// (the player handles both).
  Future<PreviewStream> stream(String id) async =>
      PreviewStream((await _stream(id)).url);

  /// Downloads track [id] into [directory]: `audio.mp3` from a progressive
  /// stream, or `audio.m4a` assembled from HLS segments.
  Future<File> downloadAudio(
    String id,
    Directory directory, {
    void Function(double progress)? onProgress,
  }) async {
    final (:url, :hls) = await _stream(id);
    final target = File('${directory.path}/audio.${hls ? 'm4a' : 'mp3'}');
    if (hls) {
      await downloadHls(_http, Uri.parse(url), target, onProgress: onProgress);
    } else {
      await downloadWhole(
        _http,
        Uri.parse(url),
        target,
        onProgress: onProgress,
      );
    }
    return target;
  }

  Future<({String url, bool hls})> _stream(String id) async {
    final track = await _apiObject('/tracks/$id', const {});
    final transcoding = _transcoding(track);
    if (transcoding == null) {
      throw const DownloadException(
        DownloadFailure.failed,
        'this track has no downloadable stream',
      );
    }
    final auth = track['track_authorization'] as String?;
    final streamInfo = jsonDecode(
      await fetchText(
        _http,
        Uri.parse(transcoding['url']! as String).replace(
          queryParameters: {
            'client_id': await _getClientId(),
            'track_authorization': ?auth,
          },
        ),
      ),
    ) as Map<String, Object?>;
    final protocol =
        (transcoding['format'] as Map<String, Object?>)['protocol'];
    return (url: streamInfo['url']! as String, hls: protocol == 'hls');
  }

  /// How track [t] can be fetched: a progressive MP3 where SoundCloud still
  /// offers one (rare since 2025), else unencrypted HLS AAC, best quality
  /// first. Encrypted HLS is DRM and the adaptive "abr" playlist answers
  /// 404, so neither counts. Null when nothing usable is left.
  static Map<String, Object?>? _transcoding(Map<String, Object?> t) {
    final all =
        ((t['media'] as Map<String, Object?>?)?['transcodings']
                    as List<Object?>? ??
                const [])
            .cast<Map<String, Object?>>();
    String? field(Map<String, Object?> x, String key) =>
        (x['format'] as Map<String, Object?>?)?[key] as String?;
    final progressive = all.where((x) => field(x, 'protocol') == 'progressive');
    final hlsAac =
        all
            .where(
              (x) =>
                  field(x, 'protocol') == 'hls' &&
                  (field(x, 'mime_type') ?? '').startsWith('audio/mp4'),
            )
            .toList()
          ..sort((a, b) => _kbps(b).compareTo(_kbps(a)));
    return progressive.firstOrNull ?? hlsAac.firstOrNull;
  }

  /// Bitrate from a preset name like `aac_160k` (0 when unknown).
  static int _kbps(Map<String, Object?> transcoding) =>
      int.tryParse(
        RegExp(r'(\d+)k').firstMatch('${transcoding['preset']}')?.group(1) ??
            '',
      ) ??
      0;

  // Short links (on.soundcloud.com/xyz) redirect to the real URL.
  Future<String> _expand(String url) async {
    if (!url.contains('on.soundcloud.com')) return url;
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = false
      ..headers['User-Agent'] = browserUserAgent;
    final response = await _http.send(request);
    return response.headers['location'] ?? url;
  }

  // Playlists only embed the first few tracks in full; fetch the rest.
  Future<List<Map<String, Object?>>> _fullTracks(
    List<Map<String, Object?>> tracks,
  ) async {
    final missing = [
      for (final t in tracks)
        if (t['title'] == null) t['id'].toString(),
    ];
    final fetched = <String, Map<String, Object?>>{};
    for (var i = 0; i < missing.length; i += 50) {
      final ids = missing.skip(i).take(50).join(',');
      final batch = await _apiList('/tracks', {'ids': ids});
      for (final t in batch) {
        fetched[t['id'].toString()] = t;
      }
    }
    return [
      for (final t in tracks)
        if (t['title'] != null) t else ?fetched[t['id'].toString()],
    ];
  }

  DownloadCandidate _candidate(
    Map<String, Object?> t, {
    String? album,
    int? trackNumber,
  }) {
    final user = (t['user'] as Map<String, Object?>?)?['username'] as String?;
    final publisherArtist =
        (t['publisher_metadata'] as Map<String, Object?>?)?['artist']
            as String?;
    final names = MetadataCleanup.fromUpload(
      title: t['title']! as String,
      uploader: publisherArtist ?? user ?? '',
    );
    final created = DateTime.tryParse(t['created_at'] as String? ?? '');
    return DownloadCandidate(
      service: MusicService.soundcloud,
      sourceId: t['id'].toString(),
      sourceUrl: t['permalink_url']! as String,
      title: names.title,
      artist: names.artist,
      durationMs: (t['duration'] as num?)?.toInt() ?? 0,
      coverUrl: _artwork(t),
      year: created?.year,
      album: album,
      trackNumber: trackNumber,
    );
  }

  /// Full-size artwork (the API returns 100 px "-large" by default).
  static String? _artwork(Map<String, Object?> data) {
    final url =
        data['artwork_url'] as String? ??
        (data['user'] as Map<String, Object?>?)?['avatar_url'] as String?;
    return url?.replaceFirst('-large.', '-t500x500.');
  }

  Future<Map<String, Object?>> _apiObject(
    String path,
    Map<String, String> params,
  ) async => jsonDecode(await _call(path, params)) as Map<String, Object?>;

  Future<List<Map<String, Object?>>> _apiList(
    String path,
    Map<String, String> params,
  ) async => (jsonDecode(await _call(path, params)) as List<Object?>)
      .cast<Map<String, Object?>>();

  Future<String> _call(String path, Map<String, String> params) async {
    Uri uri(String id) =>
        Uri.parse('$_api$path')
            .replace(queryParameters: {...params, 'client_id': id});
    try {
      return await fetchText(_http, uri(await _getClientId()));
    } on DownloadException catch (e) {
      // A rotated client_id answers 401/403: look it up again once.
      if (e.reason != DownloadFailure.network) rethrow;
      _clientId = null;
      return fetchText(_http, uri(await _getClientId()));
    }
  }

  Future<String> _getClientId() async {
    if (_clientId != null) return _clientId!;
    final home = await fetchText(_http, Uri.parse('https://soundcloud.com/'));
    final scripts = RegExp(r'https://a-v2\.sndcdn\.com/assets/[^"]+\.js')
        .allMatches(home)
        .map((m) => m.group(0)!)
        .toList();
    // The id lives in one of the last scripts.
    for (final script in scripts.reversed) {
      final js = await fetchText(_http, Uri.parse(script));
      final match = RegExp(r'client_id:"([A-Za-z0-9]{32})"').firstMatch(js);
      if (match != null) return _clientId = match.group(1)!;
    }
    throw const DownloadException(
      DownloadFailure.failed,
      'SoundCloud changed its website; update ViPlayer',
    );
  }
}
