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
    this.likedAt,
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

  /// When it was liked (ms since epoch) — orders the Liked list.
  final int? likedAt;
  final int addedAt;

  /// Local audio file, or a stream URL for a track that lives on another
  /// device at home ([isRemote]).
  final String path;

  bool get isRemote => path.startsWith('http');

  /// Cover image: a local path, or a URL for remote tracks.
  final String? coverPath;

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

enum TrackSort { title, artist, album, recentlyAdded }

/// The library in memory, with search. Built from the track list: even 20k
/// tracks take milliseconds, and every view and search becomes instant.
class LibraryIndex {
  LibraryIndex._(this.tracks);

  factory LibraryIndex.build(List<LibraryTrack> tracks) =>
      LibraryIndex._(tracks);

  final List<LibraryTrack> tracks;

  static final empty = LibraryIndex.build(const []);

  bool get isEmpty => tracks.isEmpty;

  int get totalDurationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  /// Every word of [query] must match the start of a word in the title,
  /// artist or album ("neo ra" finds "Neon Rain").
  List<LibraryTrack> search(String query) {
    final words = Fingerprint.normalize(query).split(' ')
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    return [
      for (final t in tracks)
        if (_matches(
          ' ${Fingerprint.normalize('${t.title} ${t.artist} ${t.album}')}',
          words,
        ))
          t,
    ];
  }

  static bool _matches(String haystack, List<String> words) =>
      words.every((w) => haystack.contains(' $w'));

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

  /// Case-insensitive for every script; empty strings sort last.
  static int _compareText(String a, String b) {
    if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static int _firstNonZero(List<int> results) =>
      results.firstWhere((r) => r != 0, orElse: () => 0);
}
