import 'package:flutter/foundation.dart';

import 'fingerprint.dart';

/// A track that has a playable file on this device.
@immutable
class LibraryTrack {
  const LibraryTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.liked,
    required this.addedAt,
    required this.path,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.coverPath,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int durationMs;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final bool liked;
  final int addedAt;

  /// Local audio file.
  final String path;

  /// Absolute path of the cover image, if the track has one.
  final String? coverPath;

  /// Artist an album is filed under (album artist wins for compilations).
  String get albumOwner => albumArtist ?? artist;

  /// Groups tracks into albums; case/punctuation-insensitive.
  String get albumKey =>
      '${Fingerprint.normalize(albumOwner)}|${Fingerprint.normalize(album)}';

  @override
  bool operator ==(Object other) =>
      other is LibraryTrack &&
      other.id == id &&
      other.path == path &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.liked == liked &&
      other.coverPath == coverPath &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(id, path, liked, coverPath);
}

@immutable
class Album {
  const Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.tracks,
    this.year,
    this.coverPath,
  });

  final String key;
  final String title;
  final String artist;
  final int? year;
  final String? coverPath;

  /// In disc/track order.
  final List<LibraryTrack> tracks;

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);
}

@immutable
class Artist {
  const Artist({
    required this.name,
    required this.tracks,
    required this.albums,
    this.coverPath,
  });

  final String name;
  final List<LibraryTrack> tracks;
  final List<Album> albums;
  final String? coverPath;
}

enum TrackSort { title, artist, album, recentlyAdded }

/// The local library grouped into albums and artists, plus a search index.
/// Built in memory from the track list: even 20k tracks take milliseconds,
/// and every view and search becomes instant.
class LibraryIndex {
  LibraryIndex._(this.tracks, this.albums, this.artists, this._albumsByKey);

  factory LibraryIndex.build(List<LibraryTrack> tracks) {
    final albumGroups = <String, List<LibraryTrack>>{};
    final artistGroups = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      if (t.album.isNotEmpty) {
        albumGroups.putIfAbsent(t.albumKey, () => []).add(t);
      }
      final artistKey = Fingerprint.normalize(t.artist);
      artistGroups.putIfAbsent(artistKey, () => []).add(t);
    }

    final albums = [
      for (final MapEntry(:key, value: list) in albumGroups.entries)
        _album(key, list),
    ]..sort((a, b) => _compareText(a.title, b.title));
    final albumsByKey = {for (final a in albums) a.key: a};

    final artists = [
      for (final MapEntry(:key, value: list) in artistGroups.entries)
        if (key.isNotEmpty)
          Artist(
            name: list.first.artist,
            tracks: sortTracks(list, TrackSort.album),
            albums: [
              for (final k in list.map((t) => t.albumKey).toSet())
                ?albumsByKey[k],
            ]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0)),
            coverPath: list
                .firstWhere(
                  (t) => t.coverPath != null,
                  orElse: () => list.first,
                )
                .coverPath,
          ),
    ]..sort((a, b) => _compareText(a.name, b.name));

    return LibraryIndex._(tracks, albums, artists, albumsByKey);
  }

  final List<LibraryTrack> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final Map<String, Album> _albumsByKey;

  static final empty = LibraryIndex.build(const []);

  bool get isEmpty => tracks.isEmpty;

  Album? albumByKey(String key) => _albumsByKey[key];

  Artist? artistByName(String name) {
    final key = Fingerprint.normalize(name);
    return artists
        .where((a) => Fingerprint.normalize(a.name) == key)
        .firstOrNull;
  }

  int get totalDurationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  /// Every word of [query] must match the start of a word in the title,
  /// artist or album ("neo ra" finds "Neon Rain").
  LibrarySearchResult search(String query) {
    final words = Fingerprint.normalize(query).split(' ')
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const LibrarySearchResult.empty();

    bool matches(String text) {
      final haystack = ' ${Fingerprint.normalize(text)}';
      return words.every((w) => haystack.contains(' $w'));
    }

    return LibrarySearchResult(
      tracks: [
        for (final t in tracks)
          if (matches('${t.title} ${t.artist} ${t.album}')) t,
      ],
      albums: [
        for (final a in albums)
          if (matches('${a.title} ${a.artist}')) a,
      ],
      artists: [
        for (final a in artists)
          if (matches(a.name)) a,
      ],
    );
  }

  static List<LibraryTrack> sortTracks(
    List<LibraryTrack> tracks,
    TrackSort sort,
  ) {
    final sorted = [...tracks];
    switch (sort) {
      case TrackSort.title:
        sorted.sort((a, b) => _compareText(a.title, b.title));
      case TrackSort.artist:
        sorted.sort(
          (a, b) => _firstNonZero([
            _compareText(a.artist, b.artist),
            _compareText(a.title, b.title),
          ]),
        );
      case TrackSort.album:
        sorted.sort(
          (a, b) => _firstNonZero([
            _compareText(a.album, b.album),
            (a.discNumber ?? 0).compareTo(b.discNumber ?? 0),
            (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
            _compareText(a.title, b.title),
          ]),
        );
      case TrackSort.recentlyAdded:
        sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
    return sorted;
  }

  static Album _album(String key, List<LibraryTrack> list) {
    final tracks = sortTracks(list, TrackSort.album);
    final first = tracks.first;
    return Album(
      key: key,
      title: first.album,
      artist: first.albumOwner,
      year: tracks.map((t) => t.year).nonNulls.firstOrNull,
      coverPath: tracks.map((t) => t.coverPath).nonNulls.firstOrNull,
      tracks: tracks,
    );
  }

  /// Case-insensitive for every script; empty strings sort last.
  static int _compareText(String a, String b) {
    if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static int _firstNonZero(List<int> results) =>
      results.firstWhere((r) => r != 0, orElse: () => 0);
}

@immutable
class LibrarySearchResult {
  const LibrarySearchResult({
    required this.tracks,
    required this.albums,
    required this.artists,
  });

  const LibrarySearchResult.empty()
    : tracks = const [],
      albums = const [],
      artists = const [];

  final List<LibraryTrack> tracks;
  final List<Album> albums;
  final List<Artist> artists;

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}
