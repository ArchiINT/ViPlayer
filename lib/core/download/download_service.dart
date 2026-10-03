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
    required this._tagger,
    this._ytdlp,
    YoutubeSource? youtube,
    SoundCloudSource? soundcloud,
    SpotifySource? spotify,
  }) : _http = client,
       _import = importFile,
       _youtube = youtube ?? YoutubeSource(),
       _soundcloud = soundcloud ?? SoundCloudSource(client),
       _spotify = spotify ?? SpotifySource(client);

  final http.Client _http;
  final String downloadDirectory;
  final LibraryRepository _library;
  final Future<String> Function(String path) _import;
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
      if (_ytdlp != null) {
        audio = await _ytdlp.download(
          audioUrl,
          format: format,
          directory: work.path,
          onProgress: progress,
          cancel: cancel,
        );
      } else {
        audio = File(p.join(work.path, 'audio.mp3'));
        await _soundcloud.downloadAudio(
          c.sourceId,
          audio,
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
