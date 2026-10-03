// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // Upgrading must keep every row the user already has. One realistic row per
  // table; the new coverId column starts out empty.
  test('migration from v1 to v2 keeps all data', () async {
    final oldTracksData = [
      const v1.TracksData(
        id: 't1',
        updatedAt: 10,
        deleted: 0,
        fingerprint: 'm:artist|song|60',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        source: 'local',
        liked: 1,
        likedAt: 11,
        addedAt: 9,
      ),
    ];
    final expectedNewTracksData = [
      const v2.TracksData(
        id: 't1',
        updatedAt: 10,
        deleted: 0,
        fingerprint: 'm:artist|song|60',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        source: 'local',
        liked: 1,
        likedAt: 11,
        addedAt: 9,
      ),
    ];

    final oldPlaylistsData = [
      const v1.PlaylistsData(
        id: 'p1',
        updatedAt: 12,
        deleted: 0,
        name: 'Road',
        isOffline: 1,
        createdAt: 12,
      ),
    ];
    final expectedNewPlaylistsData = [
      const v2.PlaylistsData(
        id: 'p1',
        updatedAt: 12,
        deleted: 0,
        name: 'Road',
        isOffline: 1,
        createdAt: 12,
      ),
    ];

    final oldPlaylistEntriesData = [
      const v1.PlaylistEntriesData(
        id: 'e1',
        updatedAt: 13,
        deleted: 0,
        playlistId: 'p1',
        trackId: 't1',
        position: 1.5,
        addedAt: 13,
      ),
    ];
    final expectedNewPlaylistEntriesData = [
      const v2.PlaylistEntriesData(
        id: 'e1',
        updatedAt: 13,
        deleted: 0,
        playlistId: 'p1',
        trackId: 't1',
        position: 1.5,
        addedAt: 13,
      ),
    ];

    final oldPlayEventsData = [
      const v1.PlayEventsData(
        id: 'h1',
        updatedAt: 14,
        deleted: 0,
        trackId: 't1',
        playedAt: 14,
        listenedMs: 90000,
        deviceId: 'pc',
      ),
    ];
    final expectedNewPlayEventsData = [
      const v2.PlayEventsData(
        id: 'h1',
        updatedAt: 14,
        deleted: 0,
        trackId: 't1',
        playedAt: 14,
        listenedMs: 90000,
        deviceId: 'pc',
      ),
    ];

    final oldLibraryFoldersData = [
      const v1.LibraryFoldersData(
        id: 1,
        path: '/music',
        enabled: 1,
        addedAt: 1,
      ),
    ];
    final expectedNewLibraryFoldersData = [
      const v2.LibraryFoldersData(
        id: 1,
        path: '/music',
        enabled: 1,
        addedAt: 1,
      ),
    ];

    final oldTrackFilesData = [
      const v1.TrackFilesData(
        id: 1,
        trackId: 't1',
        path: '/music/song.m4a',
        sizeBytes: 1000,
        modifiedAt: 5,
        folderId: 1,
      ),
    ];
    final expectedNewTrackFilesData = [
      const v2.TrackFilesData(
        id: 1,
        trackId: 't1',
        path: '/music/song.m4a',
        sizeBytes: 1000,
        modifiedAt: 5,
        folderId: 1,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.tracks, oldTracksData);
        batch.insertAll(oldDb.playlists, oldPlaylistsData);
        batch.insertAll(oldDb.playlistEntries, oldPlaylistEntriesData);
        batch.insertAll(oldDb.playEvents, oldPlayEventsData);
        batch.insertAll(oldDb.libraryFolders, oldLibraryFoldersData);
        batch.insertAll(oldDb.trackFiles, oldTrackFilesData);
      },
      validateItems: (newDb) async {
        expect(expectedNewTracksData, await newDb.select(newDb.tracks).get());
        expect(
          expectedNewPlaylistsData,
          await newDb.select(newDb.playlists).get(),
        );
        expect(
          expectedNewPlaylistEntriesData,
          await newDb.select(newDb.playlistEntries).get(),
        );
        expect(
          expectedNewPlayEventsData,
          await newDb.select(newDb.playEvents).get(),
        );
        expect(
          expectedNewLibraryFoldersData,
          await newDb.select(newDb.libraryFolders).get(),
        );
        expect(
          expectedNewTrackFilesData,
          await newDb.select(newDb.trackFiles).get(),
        );
      },
    );
  });

  // v3 adds sync revisions: every existing row must get one (so the first
  // sync sends it) and nothing else may change.
  test('migration from v2 to v3 keeps data and assigns revisions', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old
        .into(old.tracks)
        .insert(
          const v2.TracksData(
            id: 't1',
            updatedAt: 10,
            deleted: 0,
            fingerprint: 'fp',
            title: 'Song',
            artist: 'A',
            album: '',
            durationMs: 1,
            source: 'local',
            liked: 1,
            likedAt: 11,
            addedAt: 9,
          ),
        );
    await old
        .into(old.playlists)
        .insert(
          const v2.PlaylistsData(
            id: 'p1',
            updatedAt: 12,
            deleted: 0,
            name: 'Road',
            isOffline: 0,
            createdAt: 12,
          ),
        );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    final track = await db.select(db.tracks).getSingle();
    final playlist = await db.select(db.playlists).getSingle();
    expect(track.title, 'Song');
    expect(track.updatedAt, 10, reason: 'sync timestamps untouched');
    expect(track.liked, isTrue);
    expect(track.localRev, greaterThan(0));
    expect(playlist.localRev, greaterThan(0));
    expect(playlist.localRev, isNot(track.localRev));
    expect(await db.currentRev(), 2);
    await db.close();
  });
}
