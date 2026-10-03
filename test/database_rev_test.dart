import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  TracksCompanion track(String id) => TracksCompanion.insert(
    id: id,
    updatedAt: 1,
    fingerprint: 'fp-$id',
    title: id,
    addedAt: 1,
  );

  Future<int> revOf(String id) async => (await (db.select(
    db.tracks,
  )..where((t) => t.id.equals(id))).getSingle()).localRev;

  test('every insert and update gets the next revision', () async {
    await db.into(db.tracks).insert(track('a'));
    await db.into(db.tracks).insert(track('b'));
    expect(await revOf('a'), 1);
    expect(await revOf('b'), 2);

    await (db.update(db.tracks)..where((t) => t.id.equals('a'))).write(
      const TracksCompanion(liked: Value(true)),
    );
    expect(await revOf('a'), 3);
    expect(await db.currentRev(), 3);
  });

  test('revisions are shared across synced tables', () async {
    await db.into(db.tracks).insert(track('a'));
    await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: 'p',
            updatedAt: 1,
            name: 'P',
            createdAt: 1,
          ),
        );
    final p = await db.select(db.playlists).getSingle();
    expect(p.localRev, 2);
  });

  test('local tables are not counted', () async {
    await db
        .into(db.libraryFolders)
        .insert(LibraryFoldersCompanion.insert(path: '/m', addedAt: 1));
    expect(await db.currentRev(), 0);
  });
}
