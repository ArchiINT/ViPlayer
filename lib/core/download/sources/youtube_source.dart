import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../download_models.dart';
import '../metadata_cleanup.dart';

/// YouTube / YouTube Music metadata in pure Dart: link resolution and search
/// (the latter finds Spotify tracks on YouTube).
///
/// Audio is downloaded by yt-dlp on the desktop only: YouTube now requires
/// running its player JavaScript to unlock full streams, which pure Dart
/// cannot do (see docs/DOWNLOADS.md).
class YoutubeSource {
  YoutubeSource() : _yt = yt.YoutubeExplode();

  final yt.YoutubeExplode _yt;

  static String watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';

  /// Square-ish artwork: YouTube thumbnails are 16:9; callers crop.
  static String thumbnailUrl(String id) =>
      'https://i.ytimg.com/vi/$id/maxresdefault.jpg';
  static String fallbackThumbnailUrl(String id) =>
      'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  Future<DownloadCandidate> video(String id) async {
    try {
      return _candidate(await _yt.videos.get(id));
    } on yt.VideoUnavailableException {
      throw const DownloadException(DownloadFailure.notFound);
    } on Exception catch (e) {
      throw DownloadException(DownloadFailure.network, '$e');
    }
  }

  Future<ResolvedLink> playlist(String id, {bool isAlbum = false}) async {
    try {
      final playlist = await _yt.playlists.get(id);
      final videos = await _yt.playlists.getVideos(id).toList();
      var title = playlist.title;
      // YouTube Music album playlists are titled "Album - Album Name".
      if (isAlbum) title = title.replaceFirst(RegExp(r'^Album\s+-\s+'), '');
      return ResolvedLink(
        service: MusicService.youtube,
        collectionTitle: title,
        items: [
          for (final (i, v) in videos.indexed)
            _candidate(v).copyWithAlbum(
              isAlbum ? title : null,
              trackNumber: isAlbum ? i + 1 : null,
            ),
        ],
      );
    } on yt.YoutubeExplodeException {
      throw const DownloadException(DownloadFailure.notFound);
    } on Exception catch (e) {
      throw DownloadException(DownloadFailure.network, '$e');
    }
  }

  /// Plain YouTube search; used to find Spotify tracks on YouTube.
  Future<List<DownloadCandidate>> search(String query, {int limit = 10}) async {
    try {
      final results = await _yt.search.search(query);
      return [for (final v in results.take(limit)) _candidate(v)];
    } on Exception catch (e) {
      throw DownloadException(DownloadFailure.network, '$e');
    }
  }

  DownloadCandidate _candidate(yt.Video v) {
    final names = MetadataCleanup.fromUpload(
      title: v.title,
      uploader: v.author,
    );
    return DownloadCandidate(
      service: MusicService.youtube,
      sourceId: v.id.value,
      sourceUrl: watchUrl(v.id.value),
      title: names.title,
      artist: names.artist,
      durationMs: v.duration?.inMilliseconds ?? 0,
      coverUrl: thumbnailUrl(v.id.value),
      year: v.uploadDate?.year,
    );
  }

  void close() => _yt.close();
}

extension on DownloadCandidate {
  DownloadCandidate copyWithAlbum(String? album, {int? trackNumber}) =>
      DownloadCandidate(
        service: service,
        sourceId: sourceId,
        sourceUrl: sourceUrl,
        title: title,
        artist: artist,
        durationMs: durationMs,
        album: album,
        coverUrl: coverUrl,
        year: year,
        trackNumber: trackNumber,
      );
}
