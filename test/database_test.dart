import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  TracksCompanion track(String id, String fingerprint) =>
      TracksCompanion.insert(
        id: id,
        updatedAt: 1,
        fingerprint: fingerprint,
        title: 'Song $id',
        addedAt: 1,
      );

  test('synced rows default to not deleted', () async {
    await db.into(db.tracks).insert(track('t1', 'fp1'));

    final row = await db.select(db.tracks).getSingle();
    expect(row.deleted, isFalse);
    expect(row.liked, isFalse);
    expect(row.source, 'local');
  });

  test('fingerprint is unique — one row per song', () async {
    await db.into(db.tracks).insert(track('t1', 'same'));

    expect(
      () => db.into(db.tracks).insert(track('t2', 'same')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('foreign keys are enforced', () async {
    expect(
      () => db
          .into(db.playlistEntries)
          .insert(
            PlaylistEntriesCompanion.insert(
              id: 'e1',
              updatedAt: 1,
              playlistId: 'missing',
              trackId: 'missing',
              position: 1,
              addedAt: 1,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('removing a library folder removes its file records', () async {
    await db.into(db.tracks).insert(track('t1', 'fp1'));
    final folderId = await db
        .into(db.libraryFolders)
        .insert(LibraryFoldersCompanion.insert(path: '/music', addedAt: 1));
    await db
        .into(db.trackFiles)
        .insert(
          TrackFilesCompanion.insert(
            trackId: 't1',
            path: '/music/a.m4a',
            sizeBytes: 10,
            modifiedAt: 1,
            folderId: Value(folderId),
          ),
        );

    await (db.delete(
      db.libraryFolders,
    )..where((f) => f.id.equals(folderId))).go();

    expect(await db.select(db.trackFiles).get(), isEmpty);
    // The track itself (synced metadata) stays.
    expect(await db.select(db.tracks).get(), hasLength(1));
  });
}
