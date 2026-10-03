import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'cover_store.dart';
import 'library_models.dart';

/// SQL shared by every query that returns playable tracks: the track (alias
/// `t`) with one local file and a cover. Join it as
///
///     SELECT ..., t.*, ${TrackQueries.fileColumns}
///     FROM ... JOIN tracks t ... ${TrackQueries.fileJoin}
///
/// Tracks without a file on this device drop out through the inner join.
abstract final class TrackQueries {
  static const fileColumns = '''
    f.path AS file_path,
    (SELECT cover_id FROM track_files
       WHERE track_id = t.id AND cover_id IS NOT NULL LIMIT 1) AS file_cover''';

  static const fileJoin = '''
    JOIN track_files f
      ON f.id = (SELECT MIN(id) FROM track_files WHERE track_id = t.id)''';
}

/// Turns rows selected with [TrackQueries] into [LibraryTrack]s.
class TrackRowMapper {
  const TrackRowMapper(this._db, this._covers);

  final AppDatabase _db;
  final CoverStore _covers;

  LibraryTrack map(QueryRow row) {
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
      likedAt: t.likedAt,
      addedAt: t.addedAt,
      path: row.read<String>('file_path'),
      coverPath: coverId == null ? null : _covers.pathFor(coverId),
    );
  }
}
