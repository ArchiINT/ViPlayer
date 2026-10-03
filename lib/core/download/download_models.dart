import 'package:flutter/foundation.dart';

/// Services ViPlayer can download from (see docs/DOWNLOADS.md).
enum MusicService { youtube, soundcloud, spotify }

/// File format of downloads. Stored in settings by [name].
enum DownloadFormat {
  /// AAC, no re-encoding — the default, plays everywhere.
  m4a,

  /// Opus, no re-encoding — best quality YouTube offers. Desktop only.
  opus,

  /// Re-encoded with ffmpeg — for old devices. Desktop only.
  mp3;

  String get extension => name;

  static DownloadFormat fromName(String? name) => DownloadFormat.values
      .firstWhere((f) => f.name == name, orElse: () => DownloadFormat.m4a);
}

/// One track found behind a link (or search), ready to be downloaded.
@immutable
class DownloadCandidate {
  const DownloadCandidate({
    required this.service,
    required this.sourceId,
    required this.sourceUrl,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.album,
    this.coverUrl,
    this.year,
    this.trackNumber,
  });

  final MusicService service;

  /// Id on that service (YouTube video id, SoundCloud track id, Spotify id).
  final String sourceId;

  /// Canonical link, stored with the track to avoid downloading it twice.
  final String sourceUrl;

  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? coverUrl;
  final int? year;
  final int? trackNumber;

  DownloadCandidate copyWith({String? album, String? coverUrl}) =>
      DownloadCandidate(
        service: service,
        sourceId: sourceId,
        sourceUrl: sourceUrl,
        title: title,
        artist: artist,
        durationMs: durationMs,
        album: album ?? this.album,
        coverUrl: coverUrl ?? this.coverUrl,
        year: year,
        trackNumber: trackNumber,
      );

  Map<String, Object?> toJson() => {
    'service': service.name,
    'sourceId': sourceId,
    'sourceUrl': sourceUrl,
    'title': title,
    'artist': artist,
    'durationMs': durationMs,
    'album': album,
    'coverUrl': coverUrl,
    'year': year,
    'trackNumber': trackNumber,
  };

  factory DownloadCandidate.fromJson(Map<String, Object?> j) =>
      DownloadCandidate(
        service: MusicService.values.byName(j['service']! as String),
        sourceId: j['sourceId']! as String,
        sourceUrl: j['sourceUrl']! as String,
        title: j['title']! as String,
        artist: j['artist']! as String,
        durationMs: (j['durationMs']! as num).toInt(),
        album: j['album'] as String?,
        coverUrl: j['coverUrl'] as String?,
        year: (j['year'] as num?)?.toInt(),
        trackNumber: (j['trackNumber'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is DownloadCandidate &&
      other.service == service &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(service, sourceId);

  @override
  String toString() => '$artist - $title ($service:$sourceId)';
}

/// What a link resolved to: one track, or a collection (album, playlist).
@immutable
class ResolvedLink {
  const ResolvedLink({
    required this.service,
    required this.items,
    this.collectionTitle,
    this.collectionCoverUrl,
  });

  final MusicService service;
  final List<DownloadCandidate> items;

  /// Album / playlist name; null for a single track.
  final String? collectionTitle;
  final String? collectionCoverUrl;

  bool get isCollection => collectionTitle != null;
}

/// Where to stream a candidate from for a preview (no download).
@immutable
class PreviewStream {
  const PreviewStream(this.url, {this.headers = const {}});

  final String url;

  /// Some streams only answer with the headers they were resolved with.
  final Map<String, String> headers;
}

/// A link the user cannot download from, with a reason the UI can show.
class DownloadException implements Exception {
  const DownloadException(this.reason, [this.detail]);

  final DownloadFailure reason;
  final String? detail;

  @override
  String toString() =>
      'DownloadException($reason${detail == null ? '' : ': $detail'})';
}

enum DownloadFailure {
  unsupportedLink,

  /// The service cannot be downloaded from on this device (YouTube/Spotify
  /// on Android — see docs/DOWNLOADS.md).
  notOnThisDevice,
  alreadyInLibrary,
  notFound,
  noMatch,
  network,
  toolMissing,
  failed,
}
