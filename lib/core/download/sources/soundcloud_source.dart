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

  /// Downloads track [id] as MP3 (SoundCloud's progressive stream).
  Future<void> downloadAudio(
    String id,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    final track = await _apiObject('/tracks/$id', const {});
    final transcodings =
        ((track['media'] as Map<String, Object?>?)?['transcodings']
                    as List<Object?>? ??
                const [])
            .cast<Map<String, Object?>>();
    final progressive = transcodings.where(
      (t) => (t['format'] as Map<String, Object?>)['protocol'] == 'progressive',
    );
    if (progressive.isEmpty) {
      throw const DownloadException(
        DownloadFailure.failed,
        'this track has no downloadable stream',
      );
    }
    final streamInfo = jsonDecode(
      await fetchText(
        _http,
        Uri.parse(progressive.first['url']! as String)
            .replace(queryParameters: {'client_id': await _getClientId()}),
      ),
    ) as Map<String, Object?>;
    await downloadWhole(
      _http,
      Uri.parse(streamInfo['url']! as String),
      target,
      onProgress: onProgress,
    );
  }

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
