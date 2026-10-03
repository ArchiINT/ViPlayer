import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Everything that changed on a device since a revision: the unit of sync.
///
/// Rows travel as Drift JSON. Their `localRev` is the sender's and is
/// ignored by the receiver, which stamps merged rows with its own. All
/// changes since the cursor go in one changeset (no pagination) so a row
/// never arrives without the rows it refers to.
class Changeset {
  const Changeset({
    required this.untilRev,
    this.tracks = const [],
    this.playlists = const [],
    this.entries = const [],
    this.events = const [],
  });

  /// The sender's revision this changeset is complete up to — the cursor
  /// for the next request.
  final int untilRev;
  final List<Map<String, Object?>> tracks;
  final List<Map<String, Object?>> playlists;
  final List<Map<String, Object?>> entries;
  final List<Map<String, Object?>> events;

  bool get isEmpty =>
      tracks.isEmpty && playlists.isEmpty && entries.isEmpty && events.isEmpty;

  int get size =>
      tracks.length + playlists.length + entries.length + events.length;

  Map<String, Object?> toJson() => {
    'v': 1,
    'untilRev': untilRev,
    'tracks': tracks,
    'playlists': playlists,
    'entries': entries,
    'events': events,
  };

  factory Changeset.fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw const FormatException('unsupported changeset version');
    }
    List<Map<String, Object?>> rows(String key) =>
        (json[key] as List<Object?>? ?? const []).cast<Map<String, Object?>>();
    return Changeset(
      untilRev: (json['untilRev']! as num).toInt(),
      tracks: rows('tracks'),
      playlists: rows('playlists'),
      entries: rows('entries'),
      events: rows('events'),
    );
  }

  /// Rows changed after [sinceRev] on [db].
  static Future<Changeset> since(
    AppDatabase db,
    int sinceRev,
  ) => db.transaction(() async {
    final until = await db.currentRev();
    Future<List<Map<String, Object?>>> rows<T extends Table, D>(
      TableInfo<T, D> table,
      Map<String, Object?> Function(D) toJson,
    ) async {
      final result = await (db.select(
        table,
      )..where((t) => CustomExpression<bool>('local_rev > $sinceRev'))).get();
      return [for (final row in result) toJson(row)];
    }

    return Changeset(
      untilRev: until,
      tracks: await rows(db.tracks, (TrackRow r) => r.toJson()),
      playlists: await rows(db.playlists, (PlaylistRow r) => r.toJson()),
      entries: await rows(
        db.playlistEntries,
        (PlaylistEntryRow r) => r.toJson(),
      ),
      events: await rows(db.playEvents, (PlayEventRow r) => r.toJson()),
    );
  });
}

/// What applying a changeset did.
class ApplyResult {
  int inserted = 0;
  int updated = 0;
  int merged = 0; // same song found under two ids, joined
  int skipped = 0; // referred to something unknown

  int get changed => inserted + updated + merged;
}

/// Merges a [Changeset] from another device into the local database.
///
/// Rules (docs/SYNC.md):
///  * last write wins per row by `updatedAt`; on a tie the row whose JSON
///    sorts higher wins, so both devices pick the same one;
///  * deletions are tombstones and merge like any other change;
///  * the same song added independently on two devices (same fingerprint,
///    different ids) becomes one track under the smaller id; the other id is
///    remembered as an alias so rows still pointing at it land correctly.
class ChangesetApplier {
  ChangesetApplier(this._db);

  final AppDatabase _db;

  Future<ApplyResult> apply(Changeset c) => _db.transaction(() async {
    // Track ids are renamed during merges; references are checked at commit.
    await _db.customStatement('PRAGMA defer_foreign_keys = ON');
    final result = ApplyResult();
    final aliases = {
      for (final a in await _db.select(_db.trackAliases).get())
        a.aliasId: a.trackId,
    };
    String resolve(String trackId) => aliases[trackId] ?? trackId;

    for (final json in c.tracks) {
      await _applyTrack(TrackRow.fromJson(json), aliases, result);
    }
    for (final json in c.playlists) {
      await _lww(
        _db.playlists,
        PlaylistRow.fromJson(json),
        (r) => r.id,
        (r) => r.updatedAt,
        (r) => r.toJson(),
        result,
      );
    }
    for (final json in c.entries) {
      final row = PlaylistEntryRow.fromJson(json);
      final entry = row.copyWith(trackId: resolve(row.trackId));
      if (!await _exists(_db.tracks, entry.trackId) ||
          !await _exists(_db.playlists, entry.playlistId)) {
        result.skipped++;
        continue;
      }
      await _lww(
        _db.playlistEntries,
        entry,
        (r) => r.id,
        (r) => r.updatedAt,
        (r) => r.toJson(),
        result,
      );
    }
    for (final json in c.events) {
      final row = PlayEventRow.fromJson(json);
      final event = row.copyWith(trackId: resolve(row.trackId));
      if (!await _exists(_db.tracks, event.trackId)) {
        result.skipped++;
        continue;
      }
      await _lww(
        _db.playEvents,
        event,
        (r) => r.id,
        (r) => r.updatedAt,
        (r) => r.toJson(),
        result,
      );
    }
    return result;
  });

  Future<void> _applyTrack(
    TrackRow remote,
    Map<String, String> aliases,
    ApplyResult result,
  ) async {
    final targetId = aliases[remote.id] ?? remote.id;
    final local = await _track(targetId);
    if (local != null) {
      await _mergeTrack(local, remote.copyWith(id: targetId), result);
      return;
    }

    final twin =
        await (_db.select(_db.tracks)
              ..where((t) => t.fingerprint.equals(remote.fingerprint)))
            .getSingleOrNull();
    if (twin == null) {
      await _db.into(_db.tracks).insert(remote);
      result.inserted++;
      return;
    }

    // Same song, two ids: keep the smaller one on every device.
    result.merged++;
    if (remote.id.compareTo(twin.id) < 0) {
      await _renameTrack(twin.id, remote.id);
      aliases[twin.id] = remote.id;
      await _mergeTrack(twin.copyWith(id: remote.id), remote, result);
    } else {
      await _addAlias(remote.id, twin.id);
      aliases[remote.id] = twin.id;
      await _mergeTrack(twin, remote.copyWith(id: twin.id), result);
    }
  }

  /// Last write wins; the local fingerprint is kept (it identifies the local
  /// files and must stay unique).
  Future<void> _mergeTrack(
    TrackRow local,
    TrackRow remote,
    ApplyResult result,
  ) async {
    if (!_remoteWins(
      local.updatedAt,
      remote.updatedAt,
      _comparable(local.copyWith(fingerprint: '').toJson()),
      _comparable(remote.copyWith(fingerprint: '').toJson()),
    )) {
      return;
    }
    await (_db.update(_db.tracks)..where((t) => t.id.equals(local.id))).write(
      // Same localRev as stored: the update trigger stamps a fresh one.
      remote.copyWith(fingerprint: local.fingerprint, localRev: local.localRev),
    );
    result.updated++;
  }

  /// Moves everything from track [from] to track [to] and drops [from].
  Future<void> _renameTrack(String from, String to) async {
    for (final table in ['track_files', 'playlist_entries', 'play_events']) {
      await _db.customStatement(
        'UPDATE $table SET track_id = ? WHERE track_id = ?',
        [to, from],
      );
    }
    await _db.customStatement('UPDATE tracks SET id = ? WHERE id = ?', [
      to,
      from,
    ]);
    await _db.customStatement(
      'UPDATE track_aliases SET track_id = ? WHERE track_id = ?',
      [to, from],
    );
    await _addAlias(from, to);
  }

  Future<void> _addAlias(String aliasId, String trackId) => _db
      .into(_db.trackAliases)
      .insertOnConflictUpdate(
        TrackAliasesCompanion.insert(aliasId: aliasId, trackId: trackId),
      );

  Future<TrackRow?> _track(String id) =>
      (_db.select(_db.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<bool> _exists<T extends Table, D>(
    TableInfo<T, D> table,
    String id,
  ) async => await _byId(table, id) != null;

  Future<D?> _byId<T extends Table, D>(TableInfo<T, D> table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM ${table.actualTableName} WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null ? null : table.map(row.data);
  }

  /// Stamps a merged row with a fresh local revision (the trigger fires
  /// because local_rev is "updated" to itself), so it syncs on to other
  /// devices like any local change.
  Future<void> _touch(String table, String id) => _db.customStatement(
    'UPDATE $table SET local_rev = local_rev WHERE id = ?',
    [id],
  );

  /// Insert, or overwrite if the remote row wins.
  Future<void> _lww<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    D remote,
    String Function(D) idOf,
    int Function(D) updatedAtOf,
    Map<String, Object?> Function(D) toJson,
    ApplyResult result,
  ) async {
    final id = idOf(remote);
    final local = await _byId(table, id);
    final insertable = remote as Insertable<D>;
    if (local == null) {
      await _db.into(table).insert(insertable); // insert trigger stamps it
      result.inserted++;
      return;
    }
    if (!_remoteWins(
      updatedAtOf(local),
      updatedAtOf(remote),
      _comparable(toJson(local)),
      _comparable(toJson(remote)),
    )) {
      return;
    }
    await _db.into(table).insertOnConflictUpdate(insertable);
    await _touch(table.actualTableName, id);
    result.updated++;
  }

  static Map<String, Object?> _comparable(Map<String, Object?> json) =>
      json..remove('localRev');

  static bool _remoteWins(
    int localUpdated,
    int remoteUpdated,
    Map<String, Object?> localJson,
    Map<String, Object?> remoteJson,
  ) {
    if (remoteUpdated != localUpdated) return remoteUpdated > localUpdated;
    final l = jsonEncode(localJson);
    final r = jsonEncode(remoteJson);
    return r.compareTo(l) > 0; // deterministic tie-break, no-op if equal
  }
}
