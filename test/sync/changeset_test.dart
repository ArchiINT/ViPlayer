import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/sync/changeset.dart';

/// Two databases standing in for the PC and the phone.
void main() {
  late AppDatabase pc;
  late AppDatabase phone;

  setUp(() {
    pc = AppDatabase(NativeDatabase.memory());
    phone = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await pc.close();
    await phone.close();
  });

  Future<void> addTrack(
    AppDatabase db,
    String id, {
    String? fingerprint,
    int updatedAt = 1,
    bool liked = false,
    bool withFile = true,
  }) async {
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            id: id,
            updatedAt: updatedAt,
            fingerprint: fingerprint ?? 'fp-$id',
            title: 'Song $id',
            liked: Value(liked),
            addedAt: 1,
          ),
        );
    if (withFile) {
      await db
          .into(db.trackFiles)
          .insert(
            TrackFilesCompanion.insert(
              trackId: id,
              path: '/m/$id-${db.hashCode}.m4a',
              sizeBytes: 1,
              modifiedAt: 1,
            ),
          );
    }
  }

  Future<void> addPlaylist(
    AppDatabase db,
    String id,
    List<String> tracks,
  ) async {
    await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: id,
            updatedAt: 1,
            name: 'List $id',
            createdAt: 1,
          ),
        );
    for (final (i, t) in tracks.indexed) {
      await db
          .into(db.playlistEntries)
          .insert(
            PlaylistEntriesCompanion.insert(
              id: '$id-$t',
              updatedAt: 1,
              playlistId: id,
              trackId: t,
              position: i + 1.0,
              addedAt: 1,
            ),
          );
    }
  }

  /// One sync round in both directions, like the real protocol does.
  Future<ApplyResult> sync(
    AppDatabase from,
    AppDatabase to, [
    int since = 0,
  ]) async {
    final changes = await Changeset.since(from, since);
    return ChangesetApplier(to).apply(Changeset.fromJson(changes.toJson()));
  }

  Future<void> both() async {
    await sync(phone, pc);
    await sync(pc, phone);
  }

  Future<List<String>> ids(AppDatabase db) async => [
    for (final t in await (db.select(
      db.tracks,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get())
      t.id,
  ];

  test('a fresh device receives everything', () async {
    await addTrack(pc, 'a');
    await addTrack(pc, 'b');
    await addPlaylist(pc, 'p', ['a', 'b']);
    await pc
        .into(pc.playEvents)
        .insert(
          PlayEventsCompanion.insert(
            id: 'e',
            updatedAt: 1,
            trackId: 'a',
            playedAt: 5,
            deviceId: 'pc',
          ),
        );

    final r = await sync(pc, phone);

    expect(r.inserted, 2 + 1 + 2 + 1);
    expect(await ids(phone), ['a', 'b']);
    expect(await phone.select(phone.playlistEntries).get(), hasLength(2));
    expect(await phone.select(phone.playEvents).get(), hasLength(1));
    // File records are local; they never travel.
    expect(
      (await phone.select(phone.trackFiles).get()).where(
        (f) => f.trackId == 'a',
      ),
      isEmpty,
    );
  });

  test('syncing again changes nothing (idempotent)', () async {
    await addTrack(pc, 'a');
    await sync(pc, phone);
    final second = await sync(pc, phone);
    expect(second.changed, 0);
  });

  test('cursor: only changes after the last sync are sent', () async {
    await addTrack(pc, 'a');
    await addTrack(pc, 'b');
    final first = await Changeset.since(pc, 0);
    expect(first.size, 2);

    await (pc.update(pc.tracks)..where((t) => t.id.equals('b'))).write(
      const TracksCompanion(liked: Value(true), updatedAt: Value(9)),
    );
    final next = await Changeset.since(pc, first.untilRev);
    expect(next.tracks.single['id'], 'b');
  });

  test('last write wins, in both directions', () async {
    await addTrack(pc, 'a');
    await both();

    // Phone likes it later than the PC renames it.
    await (pc.update(pc.tracks)..where((t) => t.id.equals('a'))).write(
      const TracksCompanion(title: Value('Renamed'), updatedAt: Value(10)),
    );
    await (phone.update(phone.tracks)..where((t) => t.id.equals('a'))).write(
      const TracksCompanion(liked: Value(true), updatedAt: Value(20)),
    );
    await both();

    for (final db in [pc, phone]) {
      final t = await db.select(db.tracks).getSingle();
      expect(t.liked, isTrue, reason: 'newer row wins');
      expect(t.updatedAt, 20);
    }
  });

  test('equal timestamps resolve the same way on both devices', () async {
    await addTrack(pc, 'a');
    await both();
    await (pc.update(pc.tracks)..where((t) => t.id.equals('a'))).write(
      const TracksCompanion(title: Value('PC'), updatedAt: Value(50)),
    );
    await (phone.update(phone.tracks)..where((t) => t.id.equals('a'))).write(
      const TracksCompanion(title: Value('Phone'), updatedAt: Value(50)),
    );
    await both();
    await both();
    final a = await pc.select(pc.tracks).getSingle();
    final b = await phone.select(phone.tracks).getSingle();
    expect(a.title, b.title);
  });

  test('deletions travel as tombstones', () async {
    await addPlaylist(pc, 'p', []);
    await both();
    await (pc.update(pc.playlists)..where((p) => p.id.equals('p'))).write(
      const PlaylistsCompanion(deleted: Value(true), updatedAt: Value(9)),
    );
    await both();
    expect((await phone.select(phone.playlists).getSingle()).deleted, isTrue);
  });

  group('same song added on both devices', () {
    setUp(() async {
      // Scanned independently: same fingerprint, different random ids.
      await addTrack(
        pc,
        'id-b',
        fingerprint: 'same',
        liked: true,
        updatedAt: 5,
      );
      await addTrack(phone, 'id-a', fingerprint: 'same');
      await addPlaylist(pc, 'pc-list', ['id-b']);
      await addPlaylist(phone, 'phone-list', ['id-a']);
    });

    test('becomes one track under the smaller id everywhere', () async {
      await both();

      expect(await ids(pc), ['id-a']);
      expect(await ids(phone), ['id-a']);
      for (final db in [pc, phone]) {
        final t = await db.select(db.tracks).getSingle();
        expect(t.liked, isTrue, reason: 'newer metadata kept');
        final entries = await db.select(db.playlistEntries).get();
        expect(entries.map((e) => e.trackId).toSet(), {'id-a'});
        expect(entries, hasLength(2), reason: 'both playlists kept');
      }
      // The PC's local file now belongs to the merged track.
      expect((await pc.select(pc.trackFiles).getSingle()).trackId, 'id-a');
    });

    test('rows sent later under the old id still land', () async {
      // PC first: the phone sees id-b, keeps its own id-a and remembers
      // id-b as an alias.
      await sync(pc, phone);
      await sync(phone, pc);
      // The PC (which had id-b) adds the song to a playlist, but this change
      // was made before it learned the new id — simulate an old reference.
      await pc
          .into(pc.playEvents)
          .insert(
            PlayEventsCompanion.insert(
              id: 'late',
              updatedAt: 30,
              trackId: 'id-a',
              playedAt: 30,
              deviceId: 'pc',
            ),
          );
      final late = (await Changeset.since(pc, 0)).toJson();
      ((late['events']! as List).single as Map)['trackId'] = 'id-b';
      final r = await ChangesetApplier(phone).apply(Changeset.fromJson(late));
      expect(r.skipped, 0);
      expect(
        (await phone.select(phone.playEvents).getSingle()).trackId,
        'id-a',
      );
    });
  });

  test('applied rows get local revisions and sync onward', () async {
    final third = AppDatabase(NativeDatabase.memory());
    addTearDown(third.close);
    await addTrack(pc, 'a');
    await sync(pc, phone);
    // The phone passes the PC's track on to a third device.
    await sync(phone, third);
    expect(await ids(third), ['a']);
  });
}
