import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/library/collections_repository.dart';
import 'package:viplayer/core/library/cover_store.dart';

void main() {
  late AppDatabase db;
  late CollectionsRepository repo;

  Future<void> addTrack(String id, {bool withFile = true}) async {
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            id: id,
            updatedAt: 1,
            fingerprint: 'fp-$id',
            title: 'Song $id',
            addedAt: 1,
          ),
        );
    if (withFile) {
      await db
          .into(db.trackFiles)
          .insert(
            TrackFilesCompanion.insert(
              trackId: id,
              path: '/m/$id.m4a',
              sizeBytes: 1,
              modifiedAt: 1,
            ),
          );
    }
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = CollectionsRepository(db, const CoverStore('/covers'));
    for (final id in ['a', 'b', 'c', 'd']) {
      await addTrack(id);
    }
  });
  tearDown(() => db.close());

  Future<List<String>> itemIds(String playlistId) async => [
    for (final i in await repo.watchPlaylistItems(playlistId).first) i.track.id,
  ];

  group('likes', () {
    test('like and unlike, with timestamps for sync', () async {
      await repo.setLiked('a', liked: true);
      var row = await (db.select(
        db.tracks,
      )..where((t) => t.id.equals('a'))).getSingle();
      expect(row.liked, isTrue);
      expect(row.likedAt, isNotNull);
      expect(row.updatedAt, greaterThan(1));

      await repo.setLiked('a', liked: false);
      row = await (db.select(
        db.tracks,
      )..where((t) => t.id.equals('a'))).getSingle();
      expect(row.liked, isFalse);
      expect(row.likedAt, isNull);
    });
  });

  group('playlists', () {
    test('create, add (skipping duplicates), list with counts', () async {
      final id = await repo.createPlaylist('  Road  ');

      expect(await repo.addToPlaylist(id, ['a', 'b']), 2);
      expect(await repo.addToPlaylist(id, ['b', 'c']), 1);

      expect(await itemIds(id), ['a', 'b', 'c']);
      final summary = (await repo.watchPlaylists().first).single;
      expect(summary.name, 'Road');
      expect(summary.trackCount, 3);
    });

    test('tracks without a local file are hidden but kept', () async {
      await addTrack('remote', withFile: false);
      final id = await repo.createPlaylist('Mixed');
      await repo.addToPlaylist(id, ['a', 'remote']);

      expect(await itemIds(id), ['a']);
      expect((await repo.watchPlaylists().first).single.trackCount, 1);
      expect(await db.select(db.playlistEntries).get(), hasLength(2));
    });

    test('moving an entry rewrites only that entry', () async {
      final id = await repo.createPlaylist('Order');
      await repo.addToPlaylist(id, ['a', 'b', 'c', 'd']);
      final items = await repo.watchPlaylistItems(id).first;
      final before = {
        for (final e in await db.select(db.playlistEntries).get())
          e.id: e.updatedAt,
      };

      // d between a and b
      await repo.moveEntry(
        id,
        items[3].entryId,
        afterEntryId: items[0].entryId,
        beforeEntryId: items[1].entryId,
      );
      expect(await itemIds(id), ['a', 'd', 'b', 'c']);

      final changed = [
        for (final e in await db.select(db.playlistEntries).get())
          if (e.updatedAt != before[e.id]) e.id,
      ];
      expect(changed, [items[3].entryId]);

      // a to the end, d to the start
      await repo.moveEntry(
        id,
        items[0].entryId,
        afterEntryId: items[2].entryId,
      );
      final now = await repo.watchPlaylistItems(id).first;
      await repo.moveEntry(
        id,
        now.last.entryId,
        beforeEntryId: now.first.entryId,
      );
      expect(await itemIds(id), ['a', 'd', 'b', 'c']);
    });

    test('repeated moves into the same gap stay ordered', () async {
      final id = await repo.createPlaylist('Precision');
      await repo.addToPlaylist(id, ['a', 'b', 'c']);
      for (var i = 0; i < 80; i++) {
        final items = await repo.watchPlaylistItems(id).first;
        // Keep moving the last entry right after the first one.
        await repo.moveEntry(
          id,
          items.last.entryId,
          afterEntryId: items[0].entryId,
          beforeEntryId: items[1].entryId,
        );
      }
      final ids = await itemIds(id);
      expect(ids.first, 'a');
      expect(ids.toSet(), {'a', 'b', 'c'});
    });

    test('remove and delete leave tombstones for sync', () async {
      final id = await repo.createPlaylist('Temp');
      await repo.addToPlaylist(id, ['a', 'b']);
      final items = await repo.watchPlaylistItems(id).first;

      await repo.removeFromPlaylist(items.first.entryId);
      expect(await itemIds(id), ['b']);

      await repo.deletePlaylist(id);
      expect(await repo.watchPlaylists().first, isEmpty);
      final entries = await db.select(db.playlistEntries).get();
      expect(entries.every((e) => e.deleted), isTrue);
      expect((await db.select(db.playlists).get()).single.deleted, isTrue);
      expect(await db.select(db.tracks).get(), hasLength(4)); // untouched
    });

    test('rename and offline flag', () async {
      final id = await repo.createPlaylist('Old');
      await repo.renamePlaylist(id, 'New');
      await repo.setPlaylistOffline(id, offline: true);

      final p = (await repo.watchPlaylists().first).single;
      expect(p.name, 'New');
      expect(p.isOffline, isTrue);
    });
  });

  group('history', () {
    test('recently played: distinct, newest first; clear hides all', () async {
      await repo.recordPlay(trackId: 'a', listenedMs: 1, deviceId: 'pc');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.recordPlay(trackId: 'b', listenedMs: 1, deviceId: 'pc');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.recordPlay(trackId: 'a', listenedMs: 1, deviceId: 'pc');

      final recent = await repo.watchRecentlyPlayed().first;
      expect([for (final t in recent) t.id], ['a', 'b']);

      await repo.clearHistory();
      expect(await repo.watchRecentlyPlayed().first, isEmpty);
      expect(await db.select(db.playEvents).get(), hasLength(3));
    });
  });
}
