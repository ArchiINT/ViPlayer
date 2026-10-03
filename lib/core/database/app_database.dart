import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistEntries,
    PlayEvents,
    LibraryFolders,
    TrackFiles,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  /// Bump on every schema change and add a step to [migration].
  ///
  /// Schema snapshots live in `drift_schemas/` and are verified by tests —
  /// run `scripts/db-schema.sh` after changing tables.dart.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks (artist)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_entries_playlist '
      'ON playlist_entries (playlist_id, position)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_files_track ON track_files (track_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_events_played ON play_events (played_at)',
    );
  }

  /// The database lives in the app *support* directory (Linux:
  /// ~/.local/share/com.viplayer.app, Android: app-private storage), not in
  /// ~/Documents. App updates keep this directory intact.
  static QueryExecutor _openDefault() => driftDatabase(
    name: 'viplayer',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
