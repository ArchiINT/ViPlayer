import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../library/library_repository.dart';
import 'download_models.dart';
import 'http_download.dart';
import 'link_parser.dart';
import 'sources/soundcloud_source.dart';
import 'sources/spotify_source.dart';
import 'sources/youtube_source.dart';
import 'tools/tagger.dart';
import 'tools/ytdlp.dart';
import 'track_matcher.dart';

/// Results of searching one service.
class SearchOutcome {
  const SearchOutcome(this.items, {this.failure});

  final List<DownloadCandidate> items;

  /// Set when this service could not be searched (others may still work).
  final DownloadFailure? failure;
}

/// Steps of one download, for progress display.
enum DownloadStage { matching, downloading, tagging, saving }

/// Turns links into tracks in the library.
///
///   resolve(link) -> candidates -> download(candidate):
///     Spotify: find the same recording on YouTube (TrackMatcher)
///     fetch audio: yt-dlp (desktop) | Dart SoundCloud client (Android)
///     fetch cover -> write tags -> move into the download folder
///     -> import into the library, remember the source (no duplicates).
class DownloadService {
  DownloadService({
    required http.Client client,
    required this.downloadDirectory,
    required this._library,
    required Future<String> Function(String path) importFile,
    String? previewCacheDirectory,
    required this._tagger,
    this._ytdlp,
    YoutubeSource? youtube,
    SoundCloudSource? soundcloud,
    SpotifySource? spotify,
  }) : _http = client,
       _import = importFile,
       _previewCache = previewCacheDirectory,
       _youtube = youtube ?? YoutubeSource(),
       _soundcloud = soundcloud ?? SoundCloudSource(client),
       _spotify = spotify ?? SpotifySource(client);

  final http.Client _http;
  final String downloadDirectory;
  final LibraryRepository _library;
  final Future<String> Function(String path) _import;

  /// Where YouTube previews are fetched to (see [preview]); null disables
  /// the cache (previews then fail on YouTube).
  final String? _previewCache;
  final Tagger _tagger;

  /// Null on Android: only sources with a pure-Dart download work there.
  final YtDlp? _ytdlp;
  final YoutubeSource _youtube;
  final SoundCloudSource _soundcloud;
  final SpotifySource _spotify;

  bool get canDownloadYoutube => _ytdlp != null;

  /// Which services this device can download from.
  bool supports(MusicService service) =>
      service == MusicService.soundcloud || canDownloadYoutube;

  Future<ResolvedLink> resolve(String text) async {
    final link = LinkParser.parse(text);
    if (link == null) {
      throw const DownloadException(DownloadFailure.unsupportedLink);
    }
    return switch (link.service) {
      MusicService.youtube =>
        link.kind == LinkKind.track
            ? ResolvedLink(
                service: MusicService.youtube,
                items: [await _youtube.video(link.id)],
              )
            : await _youtube.playlist(
                link.id,
                isAlbum: link.kind == LinkKind.album,
              ),
      MusicService.soundcloud => await _soundcloud.resolve(link.url),
      MusicService.spotify => await _spotify.resolve(link),
    };
  }

  /// Services that "by name" search covers on this device: only those it can
  /// also download from.
  List<MusicService> get searchableServices => [
    if (canDownloadYoutube) MusicService.youtube,
    MusicService.soundcloud,
  ];

  /// Searches each service in [services] (in parallel). A failing service
  /// yields an error entry instead of failing the whole search.
  Future<Map<MusicService, SearchOutcome>> search(
    String query, {
    List<MusicService>? services,
  }) async {
    final wanted = services ?? searchableServices;
    final results = await Future.wait([
      for (final s in wanted) _searchOne(s, query),
    ]);
    return {for (final (i, s) in wanted.indexed) s: results[i]};
  }

  Future<SearchOutcome> _searchOne(MusicService service, String query) async {
    try {
      final items = switch (service) {
        MusicService.youtube =>
          (await _youtube.search(query, limit: 25))
              // Not songs: shorts and hour-long mixes.
              .where((c) => c.durationMs >= 30000 && c.durationMs <= 20 * 60000)
              .toList(),
        MusicService.soundcloud => await _soundcloud.search(query),
        MusicService.spotify => const <DownloadCandidate>[],
      };
      return SearchOutcome(items);
    } on DownloadException catch (e) {
      return SearchOutcome(const [], failure: e.reason);
    } on Exception {
      return const SearchOutcome([], failure: DownloadFailure.network);
    }
  }

  /// Something to listen to [c] before downloading it.
  ///
  /// SoundCloud streams directly. YouTube stream URLs are unreliable for
  /// plain players (YouTube randomly answers 403 past the first megabyte),
  /// so on the desktop the track is fetched with yt-dlp into a preview cache
  /// (~2 s) and played from the file; a later download reuses that file.
  Future<PreviewStream> preview(DownloadCandidate c) async {
    switch (c.service) {
      case MusicService.soundcloud:
        return _soundcloud.stream(c.sourceId);
      case MusicService.youtube || MusicService.spotify
          when _ytdlp != null && _previewCache != null:
        final videoUrl = c.service == MusicService.spotify
            ? (await _matchOnYoutube(c)).sourceUrl
            : c.sourceUrl;
        final file = await _cachedPreview(videoUrl);
        return PreviewStream(file.path);
      default:
        throw const DownloadException(DownloadFailure.notOnThisDevice);
    }
  }

  /// Preview file for a YouTube video, fetched once.
  Future<File> _cachedPreview(String videoUrl) async {
    final dir = Directory(
      p.join(_previewCache!, Uri.parse(videoUrl).queryParameters['v']),
    );
    final existing = dir.existsSync()
        ? dir.listSync().whereType<File>().firstOrNull
        : null;
    if (existing != null) return existing;
    await dir.create(recursive: true);
    return _ytdlp!.download(
      videoUrl,
      format: DownloadFormat.m4a,
      directory: dir.path,
    );
  }

  /// Downloads [c] into the library and returns the new track's id.
  Future<String> download(
    DownloadCandidate c, {
    required DownloadFormat format,
    void Function(DownloadStage stage, double? progress)? onProgress,
    Completer<void>? cancel,
  }) async {
    if (!supports(c.service)) {
      throw const DownloadException(DownloadFailure.notOnThisDevice);
    }
    if (await _library.hasLocalTrackFrom(c.sourceUrl)) {
      throw const DownloadException(DownloadFailure.alreadyInLibrary);
    }

    // 1. Where the audio comes from.
    var audioUrl = c.sourceUrl;
    var coverUrls = [?c.coverUrl];
    if (c.service == MusicService.spotify) {
      onProgress?.call(DownloadStage.matching, null);
      final match = await _matchOnYoutube(c);
      audioUrl = match.sourceUrl;
      coverUrls = [
        ?c.coverUrl,
        if (c.coverUrl == null) ?await _spotify.coverFor(c.sourceId),
      ];
    } else if (c.service == MusicService.youtube) {
      coverUrls = [
        YoutubeSource.thumbnailUrl(c.sourceId),
        YoutubeSource.fallbackThumbnailUrl(c.sourceId),
      ];
    }

    final work = await Directory.systemTemp.createTemp('viplayer_dl_');
    try {
      // 2. Audio.
      void progress(double v) => onProgress?.call(DownloadStage.downloading, v);
      onProgress?.call(DownloadStage.downloading, 0);
      final File audio;
      final cached = await _reusablePreview(audioUrl, format, work);
      if (cached != null) {
        audio = cached;
        progress(1);
      } else if (_ytdlp != null) {
        audio = await _ytdlp.download(
          audioUrl,
          format: format,
          directory: work.path,
          onProgress: progress,
          cancel: cancel,
        );
      } else {
        audio = await _soundcloud.downloadAudio(
          c.sourceId,
          work,
          onProgress: progress,
        );
      }
      if (cancel?.isCompleted ?? false) {
        throw const DownloadException(DownloadFailure.failed, 'cancelled');
      }

      // 3. Cover + tags.
      onProgress?.call(DownloadStage.tagging, null);
      Uint8List? cover;
      for (final url in coverUrls) {
        cover = await fetchBytes(_http, Uri.parse(url));
        if (cover != null) break;
      }
      await _tagger.write(audio, TrackTags.of(c, cover));

      // 4. Into the download folder and the library.
      onProgress?.call(DownloadStage.saving, null);
      final target = await _targetFile(c, p.extension(audio.path));
      await _move(audio, target);
      final trackId = await _import(target.path);
      await _library.markSource(
        trackId,
        source: c.service.name,
        sourceUrl: c.sourceUrl,
      );
      return trackId;
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<DownloadCandidate> _matchOnYoutube(DownloadCandidate wanted) async {
    for (final query in [
      '${wanted.artist} - ${wanted.title}',
      '${wanted.artist} ${wanted.title} audio',
    ]) {
      final match = TrackMatcher.best(wanted, await _youtube.search(query));
      if (match != null) return match;
    }
    throw const DownloadException(DownloadFailure.noMatch);
  }

  /// A preview already fetched for this video, copied into [work] — so
  /// "listen, then download" does not fetch the file twice.
  Future<File?> _reusablePreview(
    String audioUrl,
    DownloadFormat format,
    Directory work,
  ) async {
    final id = Uri.parse(audioUrl).queryParameters['v'];
    if (_previewCache == null || id == null || format != DownloadFormat.m4a) {
      return null;
    }
    final dir = Directory(p.join(_previewCache, id));
    final file = dir.existsSync()
        ? dir.listSync().whereType<File>().firstOrNull
        : null;
    return file?.copy(p.join(work.path, p.basename(file.path)));
  }

  /// Deletes cached previews (called at startup).
  static Future<void> clearPreviewCache(String directory) async {
    final dir = Directory(directory);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// `<downloads>/<Artist> - <Title>.<ext>`, made unique.
  Future<File> _targetFile(DownloadCandidate c, String extension) async {
    await Directory(downloadDirectory).create(recursive: true);
    final base = safeFileName(
      c.artist.isEmpty ? c.title : '${c.artist} - ${c.title}',
    );
    var file = File(p.join(downloadDirectory, '$base$extension'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(downloadDirectory, '$base ($n)$extension'));
    }
    return file;
  }

  /// rename() fails across file systems (/tmp is often tmpfs).
  static Future<void> _move(File from, File to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await from.copy(to.path);
      await from.delete();
    }
  }

  /// File-system-safe name: no path separators or reserved characters,
  /// bounded length.
  static String safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+'), '');
    final bounded = cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
    return bounded.isEmpty ? 'track' : bounded;
  }

  void close() => _youtube.close();
}
