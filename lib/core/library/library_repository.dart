import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import 'cover_store.dart';
import 'library_models.dart';

/// Read/write access to the local music library.
class LibraryRepository {
  LibraryRepository(this._db, this._covers);

  final AppDatabase _db;
  final CoverStore _covers;

  /// All tracks that have a file on this device. Re-emits on every change.
  ///
  /// A track with several local copies is listed once (lowest file id); its
  /// cover comes from whichever copy has one.
  Stream<List<LibraryTrack>> watchTracks() {
    return _db
        .customSelect(
          '''
          SELECT t.*,
            f.path AS file_path,
            (SELECT cover_id FROM track_files
               WHERE track_id = t.id AND cover_id IS NOT NULL
               LIMIT 1) AS file_cover
          FROM tracks t
          JOIN track_files f
            ON f.id = (SELECT MIN(id) FROM track_files WHERE track_id = t.id)
          WHERE t.deleted = 0
          ''',
          readsFrom: {_db.tracks, _db.trackFiles},
        )
        .watch()
        .map((rows) => rows.map(_toLibraryTrack).toList(growable: false));
  }

  LibraryTrack _toLibraryTrack(QueryRow row) {
    final t = _db.tracks.map(row.data);
    final coverId = row.readNullable<String>('file_cover');
    return LibraryTrack(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      albumArtist: t.albumArtist,
      durationMs: t.durationMs,
      trackNumber: t.trackNumber,
      discNumber: t.discNumber,
      year: t.year,
      genre: t.genre,
      liked: t.liked,
      addedAt: t.addedAt,
      path: row.read<String>('file_path'),
      coverPath: coverId == null ? null : _covers.pathFor(coverId),
    );
  }

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
