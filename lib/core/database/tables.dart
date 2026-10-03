import 'package:drift/drift.dart';

// Schema overview — see docs/ARCHITECTURE.md ("Database").
//
// Two kinds of tables:
//  * SYNCED tables (SyncColumns) are replicated between devices. Rows have a
//    UUID primary key, a last-modified timestamp for last-write-wins merging
//    and a soft-delete flag ("tombstone") so deletions replicate too.
//  * LOCAL tables describe this device only (file paths, scanned folders) and
//    are never sent to other devices.
//
// Any change here needs a schemaVersion bump + migration in app_database.dart.

/// Columns shared by every synced table.
mixin SyncColumns on Table {
  /// UUID v4, generated on the device that created the row.
  TextColumn get id => text()();

  /// Last modification, milliseconds since epoch (UTC). Newer wins on merge.
  IntColumn get updatedAt => integer()();

  /// Tombstone: row was deleted, kept so the deletion can sync.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A song, independent of where (or whether) its file exists on this device.
@DataClassName('TrackRow')
class Tracks extends Table with SyncColumns {
  /// Content identity used to recognise the same song on different devices,
  /// where file paths differ. See docs/SYNC.md.
  TextColumn get fingerprint => text().unique()();

  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().nullable()();

  /// Where the track came from: `local`, `youtube`, `soundcloud`, `spotify`.
  TextColumn get source => text().withDefault(const Constant('local'))();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get isrc => text().nullable()();

  BoolColumn get liked => boolean().withDefault(const Constant(false))();
  IntColumn get likedAt => integer().nullable()();
  IntColumn get addedAt => integer()();
}

@DataClassName('PlaylistRow')
class Playlists extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Offline playlists get their files copied to the phone during sync.
  BoolColumn get isOffline => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
}

/// Track membership in a playlist.
@DataClassName('PlaylistEntryRow')
class PlaylistEntries extends Table with SyncColumns {
  TextColumn get playlistId => text().references(Playlists, #id)();
  TextColumn get trackId => text().references(Tracks, #id)();

  /// Fractional ordering: inserting between 1.0 and 2.0 uses 1.5, so a move
  /// touches one row and concurrent edits on two devices merge cleanly.
  RealColumn get position => real()();
  IntColumn get addedAt => integer()();
}

/// Append-only listening history (also feeds "recently played" and stats).
@DataClassName('PlayEventRow')
class PlayEvents extends Table with SyncColumns {
  TextColumn get trackId => text().references(Tracks, #id)();
  IntColumn get playedAt => integer()();

  /// How long it was actually listened to.
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
  TextColumn get deviceId => text()();
}

/// LOCAL: folders the user picked as music sources on this device.
@DataClassName('LibraryFolderRow')
class LibraryFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get addedAt => integer()();
}

/// LOCAL: an audio file on this device and the track it belongs to.
@DataClassName('TrackFileRow')
class TrackFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text().references(Tracks, #id)();
  TextColumn get path => text().unique()();
  IntColumn get sizeBytes => integer()();

  /// File mtime (ms) — lets the scanner skip unchanged files.
  IntColumn get modifiedAt => integer()();

  /// Cover image extracted from this file (or its folder), stored in the
  /// covers directory under this name. See CoverStore. Added in schema v2.
  TextColumn get coverId => text().nullable()();

  /// Library folder the file was found in; null for the download folder and
  /// for files found through Android's MediaStore.
  IntColumn get folderId => integer().nullable().references(
    LibraryFolders,
    #id,
    onDelete: KeyAction.cascade,
  )();
}
