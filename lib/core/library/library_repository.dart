import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'cover_store.dart';
import 'library_models.dart';
import 'track_queries.dart';

/// Read/write access to the local music library.
class LibraryRepository {
  LibraryRepository(this._db, CoverStore covers)
    : _mapper = TrackRowMapper(_db, covers);

  final AppDatabase _db;
  final TrackRowMapper _mapper;

  /// All tracks that have a file on this device. Re-emits on every change.
  /// A track with several local copies is listed once.
  Stream<List<LibraryTrack>> watchTracks() {
    return _db
        .customSelect(
          'SELECT t.*, ${TrackQueries.fileColumns} '
          'FROM tracks t ${TrackQueries.fileJoin} '
          'WHERE t.deleted = 0',
          readsFrom: {_db.tracks, _db.trackFiles},
        )
        .watch()
        .map((rows) => rows.map(_mapper.map).toList(growable: false));
  }

  /// Records where a downloaded track came from (also how duplicates are
  /// recognised before downloading again).
  Future<void> markSource(
    String trackId, {
    required String source,
    required String sourceUrl,
  }) => (_db.update(_db.tracks)..where((t) => t.id.equals(trackId))).write(
    TracksCompanion(
      source: Value(source),
      sourceUrl: Value(sourceUrl),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ),
  );

  /// True if a track from [sourceUrl] already has a file on this device.
  Future<bool> hasLocalTrackFrom(String sourceUrl) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM tracks t '
          'WHERE t.source_url = ? AND t.deleted = 0 '
          'AND EXISTS (SELECT 1 FROM track_files f WHERE f.track_id = t.id) '
          'LIMIT 1',
          variables: [Variable.withString(sourceUrl)],
          readsFrom: {_db.tracks, _db.trackFiles},
        )
        .get();
    return rows.isNotEmpty;
  }

  /// Local files of [trackId] (usually one).
  Future<List<String>> filesOf(String trackId) async => [
    for (final f in await (_db.select(
      _db.trackFiles,
    )..where((f) => f.trackId.equals(trackId))).get())
      f.path,
  ];

  /// Forgets the local files of [trackId] (after they were deleted from
  /// disk) and marks the track as deleted here on purpose, so sync does not
  /// bring it back. Likes, playlists and history are kept — other devices
  /// may still have the song.
  Future<void> forgetLocalFiles(String trackId) => _db.transaction(() async {
    await (_db.delete(
      _db.trackFiles,
    )..where((f) => f.trackId.equals(trackId))).go();
    await _db
        .into(_db.excludedTracks)
        .insertOnConflictUpdate(
          ExcludedTracksCompanion.insert(
            trackId: trackId,
            excludedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  });

  /// Stores the real length measured by the player.
  Future<void> updateDuration(String trackId, int durationMs) =>
      (_db.update(_db.tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(
          durationMs: Value(durationMs),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Stream<List<LibraryFolderRow>> watchFolders() => (_db.select(
    _db.libraryFolders,
  )..orderBy([(f) => OrderingTerm.asc(f.path)])).watch();

  /// Adds a music folder. Returns false if it is already in the list.
  Future<bool> addFolder(String path) async {
    final normalized = p.normalize(path);
    return _db.transaction(() async {
      final exists = await (_db.select(
        _db.libraryFolders,
      )..where((f) => f.path.equals(normalized))).getSingleOrNull();
      if (exists != null) return false;
      await _db
          .into(_db.libraryFolders)
          .insert(
            LibraryFoldersCompanion.insert(
              path: normalized,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      return true;
    });
  }

  Future<void> setFolderEnabled(int id, {required bool enabled}) =>
      (_db.update(_db.libraryFolders)..where((f) => f.id.equals(id))).write(
        LibraryFoldersCompanion(enabled: Value(enabled)),
      );

  /// Removes the folder from the library (its file records go with it via
  /// ON DELETE CASCADE). Files on disk are never touched.
  Future<void> removeFolder(int id) =>
      (_db.delete(_db.libraryFolders)..where((f) => f.id.equals(id))).go();
}
