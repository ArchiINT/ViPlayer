import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'cover_store.dart';
import 'library_models.dart';
import 'track_queries.dart';

@immutable
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.isOffline,
    required this.trackCount,
    this.coverPath,
  });

  final String id;
  final String name;

  /// Its tracks get copied to the phone during sync (stage 7).
  final bool isOffline;

  /// Tracks playable on this device.
  final int trackCount;
  final String? coverPath;
}

/// A track's place in a playlist. The same song can appear only once per
/// playlist, but entries — not tracks — are what get moved and removed.
@immutable
class PlaylistItem {
  const PlaylistItem({
    required this.entryId,
    required this.position,
    required this.track,
  });

  final String entryId;
  final double position;
  final LibraryTrack track;
}

/// Likes, playlists and listening history — the user's own data, all of it
/// synced between devices (docs/SYNC.md).
///
/// Sync rules every write here follows: rows get UUIDs, every change bumps
/// `updated_at`, and deleting means setting the `deleted` tombstone.
class CollectionsRepository {
  CollectionsRepository(this._db, CoverStore covers)
    : _covers = covers,
      _mapper = TrackRowMapper(_db, covers);

  final AppDatabase _db;
  final CoverStore _covers;
  final TrackRowMapper _mapper;

  static const _uuid = Uuid();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------------ likes

  Future<void> setLiked(String trackId, {required bool liked}) {
    final now = _now();
    return (_db.update(_db.tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        liked: Value(liked),
        likedAt: Value(liked ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  // -------------------------------------------------------------- playlists

  /// Newest first.
  Stream<List<PlaylistSummary>> watchPlaylists() {
    return _db
        .customSelect(
          '''
          SELECT p.id, p.name, p.is_offline,
            (SELECT COUNT(*) FROM playlist_entries e
               JOIN tracks t ON t.id = e.track_id
               WHERE e.playlist_id = p.id AND e.deleted = 0 AND t.deleted = 0
                 AND EXISTS (SELECT 1 FROM track_files f
                             WHERE f.track_id = t.id)) AS track_count,
            (SELECT f.cover_id FROM playlist_entries e
               JOIN track_files f ON f.track_id = e.track_id
               WHERE e.playlist_id = p.id AND e.deleted = 0
                 AND f.cover_id IS NOT NULL
               ORDER BY e.position LIMIT 1) AS cover_id
          FROM playlists p
          WHERE p.deleted = 0
          ORDER BY p.created_at DESC
          ''',
          readsFrom: {
            _db.playlists,
            _db.playlistEntries,
            _db.tracks,
            _db.trackFiles,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              PlaylistSummary(
                id: r.read<String>('id'),
                name: r.read<String>('name'),
                isOffline: r.read<bool>('is_offline'),
                trackCount: r.read<int>('track_count'),
                coverPath: switch (r.readNullable<String>('cover_id')) {
                  final id? => _covers.pathFor(id),
                  null => null,
                },
              ),
          ],
        );
  }

  /// Playable tracks of a playlist, in order.
  Stream<List<PlaylistItem>> watchPlaylistItems(String playlistId) {
    return _db
        .customSelect(
          'SELECT e.id AS entry_id, e.position AS entry_position, t.*, '
          '${TrackQueries.fileColumns} '
          'FROM playlist_entries e JOIN tracks t ON t.id = e.track_id '
          '${TrackQueries.fileJoin} '
          'WHERE e.playlist_id = ? AND e.deleted = 0 AND t.deleted = 0 '
          'ORDER BY e.position',
          variables: [Variable.withString(playlistId)],
          readsFrom: {_db.playlistEntries, _db.tracks, _db.trackFiles},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              PlaylistItem(
                entryId: r.read<String>('entry_id'),
                position: r.read<double>('entry_position'),
                track: _mapper.map(r),
              ),
          ],
        );
  }

  Future<String> createPlaylist(String name) async {
    final id = _uuid.v4();
    final now = _now();
    await _db
        .into(_db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: id,
            updatedAt: now,
            name: name.trim(),
            createdAt: now,
          ),
        );
    return id;
  }

  Future<void> renamePlaylist(String id, String name) =>
      (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(name: Value(name.trim()), updatedAt: Value(_now())),
      );

  Future<void> setPlaylistOffline(String id, {required bool offline}) =>
      (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(isOffline: Value(offline), updatedAt: Value(_now())),
      );

  /// Tombstones the playlist and its entries. Tracks are untouched.
  Future<void> deletePlaylist(String id) => _db.transaction(() async {
    final now = _now();
    await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(deleted: const Value(true), updatedAt: Value(now)),
    );
    await (_db.update(
      _db.playlistEntries,
    )..where((e) => e.playlistId.equals(id) & e.deleted.equals(false))).write(
      PlaylistEntriesCompanion(
        deleted: const Value(true),
        updatedAt: Value(now),
      ),
    );
  });

  /// Appends tracks; ones already in the playlist are skipped. Returns how
  /// many were added.
  Future<int> addToPlaylist(String playlistId, List<String> trackIds) =>
      _db.transaction(() async {
        final existing =
            await (_db.select(_db.playlistEntries)..where(
                  (e) =>
                      e.playlistId.equals(playlistId) & e.deleted.equals(false),
                ))
                .get();
        final present = {for (final e in existing) e.trackId};
        var position = existing.fold<double>(
          0,
          (max, e) => e.position > max ? e.position : max,
        );
        final now = _now();
        var added = 0;
        for (final trackId in trackIds) {
          if (!present.add(trackId)) continue;
          position += 1;
          await _db
              .into(_db.playlistEntries)
              .insert(
                PlaylistEntriesCompanion.insert(
                  id: _uuid.v4(),
                  updatedAt: now,
                  playlistId: playlistId,
                  trackId: trackId,
                  position: position,
                  addedAt: now,
                ),
              );
          added++;
        }
        if (added > 0) await _touchPlaylist(playlistId, now);
        return added;
      });

  Future<void> removeFromPlaylist(String entryId) =>
      (_db.update(
        _db.playlistEntries,
      )..where((e) => e.id.equals(entryId))).write(
        PlaylistEntriesCompanion(
          deleted: const Value(true),
          updatedAt: Value(_now()),
        ),
      );

  /// Moves an entry so it ends up after [afterEntryId] and before
  /// [beforeEntryId] (null at either end of the list).
  ///
  /// Only the moved row changes, so concurrent edits on two devices merge.
  Future<void> moveEntry(
    String playlistId,
    String entryId, {
    String? afterEntryId,
    String? beforeEntryId,
  }) => _db.transaction(() async {
    Future<double?> positionOf(String? id) async => id == null
        ? null
        : (await (_db.select(
            _db.playlistEntries,
          )..where((e) => e.id.equals(id))).getSingleOrNull())?.position;

    var lower = await positionOf(afterEntryId);
    var upper = await positionOf(beforeEntryId);
    if (lower != null && upper != null && upper - lower < 1e-9) {
      // Ran out of precision between the two: spread positions, re-read.
      await _renumber(playlistId);
      lower = await positionOf(afterEntryId);
      upper = await positionOf(beforeEntryId);
    }

    final double position;
    if (lower == null && upper == null) {
      return;
    } else if (lower == null) {
      position = upper! - 1;
    } else if (upper == null) {
      position = lower + 1;
    } else {
      position = (lower + upper) / 2;
    }
    await (_db.update(
      _db.playlistEntries,
    )..where((e) => e.id.equals(entryId))).write(
      PlaylistEntriesCompanion(
        position: Value(position),
        updatedAt: Value(_now()),
      ),
    );
  });

  Future<void> _renumber(String playlistId) => _db.transaction(() async {
    final entries =
        await (_db.select(_db.playlistEntries)
              ..where(
                (e) =>
                    e.playlistId.equals(playlistId) & e.deleted.equals(false),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.position)]))
            .get();
    final now = _now();
    for (final (i, e) in entries.indexed) {
      await (_db.update(
        _db.playlistEntries,
      )..where((x) => x.id.equals(e.id))).write(
        PlaylistEntriesCompanion(
          position: Value(i + 1.0),
          updatedAt: Value(now),
        ),
      );
    }
  });

  Future<void> _touchPlaylist(String id, int now) =>
      (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(updatedAt: Value(now)),
      );

  // ---------------------------------------------------------------- history

  Future<void> recordPlay({
    required String trackId,
    required int listenedMs,
    required String deviceId,
  }) {
    final now = _now();
    return _db
        .into(_db.playEvents)
        .insert(
          PlayEventsCompanion.insert(
            id: _uuid.v4(),
            updatedAt: now,
            trackId: trackId,
            playedAt: now,
            listenedMs: Value(listenedMs),
            deviceId: deviceId,
          ),
        );
  }

  /// Distinct tracks, most recently played first.
  Stream<List<LibraryTrack>> watchRecentlyPlayed({int limit = 100}) {
    return _db
        .customSelect(
          'SELECT t.*, ${TrackQueries.fileColumns}, '
          'MAX(h.played_at) AS last_played '
          'FROM play_events h JOIN tracks t ON t.id = h.track_id '
          '${TrackQueries.fileJoin} '
          'WHERE h.deleted = 0 AND t.deleted = 0 '
          'GROUP BY t.id ORDER BY last_played DESC LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.playEvents, _db.tracks, _db.trackFiles},
        )
        .watch()
        .map((rows) => rows.map(_mapper.map).toList(growable: false));
  }

  /// Hides all history on every device (tombstones, so it syncs).
  Future<void> clearHistory() =>
      (_db.update(_db.playEvents)..where((h) => h.deleted.equals(false))).write(
        PlayEventsCompanion(
          deleted: const Value(true),
          updatedAt: Value(_now()),
        ),
      );
}
