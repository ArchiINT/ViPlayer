import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/library/cover_store.dart';
import 'package:viplayer/core/library/library_repository.dart';
import 'package:viplayer/core/library/library_scanner.dart';

/// Runs the real scanner over copies of test/fixtures/audio.
void main() {
  late Directory temp;
  late String music;
  late String downloads;
  late String covers;
  late AppDatabase db;
  late LibraryScanner scanner;
  late LibraryRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('viplayer_scan_');
    music = p.join(temp.path, 'music');
    downloads = p.join(temp.path, 'downloads');
    covers = p.join(temp.path, 'covers');
    await Directory(covers).create();
    await _copyDir(Directory('test/fixtures/audio'), Directory(music));

    db = AppDatabase(NativeDatabase.memory());
    scanner = LibraryScanner(db, coversDir: covers, downloadDir: downloads);
    repo = LibraryRepository(db, CoverStore(covers));
    await repo.addFolder(music);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('first scan imports every audio file with its tags', () async {
    final result = await scanner.scan();

    expect(result.added, 4);
    expect(result.totalFiles, 4);
    final tracks = {for (final t in await repo.watchTracks().first) t.title: t};
    expect(tracks.keys, {
      'Neon Rain',
      'Чёрный лёд',
      'Ghost Signal',
      'untagged_track', // no tags -> file name
    });

    final neon = tracks['Neon Rain']!;
    expect(neon.artist, 'Synth Rider');
    expect(neon.album, 'Night City');
    expect(neon.year, 2077);
    expect(neon.genre, 'Synthwave');
    expect(neon.durationMs, closeTo(3000, 100));

    expect(tracks['Чёрный лёд']!.artist, 'Кибер Волна');
  });

  test('covers: embedded picture first, folder image as fallback', () async {
    await scanner.scan();
    final tracks = {for (final t in await repo.watchTracks().first) t.title: t};

    final embedded = tracks['Neon Rain']!.coverPath!;
    final folder = tracks['Ghost Signal']!.coverPath!;
    expect(File(embedded).existsSync(), isTrue);
    expect(File(folder).existsSync(), isTrue);
    expect(embedded, isNot(folder));
    // Both tracks in album/ share the single stored folder image.
    expect(tracks['untagged_track']!.coverPath, folder);
    // Identical embedded covers are stored once.
    expect(tracks['Чёрный лёд']!.coverPath, embedded);
    expect(Directory(covers).listSync(), hasLength(2));
  });

  test('rescan of an unchanged library reads nothing', () async {
    await scanner.scan();
    final again = await scanner.scan();

    expect(again.added + again.updated + again.removed, 0);
  });

  test('deleted files disappear, their tracks are kept', () async {
    await scanner.scan();
    await File(p.join(music, 'neon_rain.m4a')).delete();

    final result = await scanner.scan();

    expect(result.removed, 1);
    final titles = (await repo.watchTracks().first).map((t) => t.title);
    expect(titles, isNot(contains('Neon Rain')));
    // Metadata (likes, playlists) survives for sync and a later re-add.
    final all = await db.select(db.tracks).get();
    expect(all.map((t) => t.title), contains('Neon Rain'));
  });

  test('a file that comes back reattaches to its old track', () async {
    await scanner.scan();
    final before = (await repo.watchTracks().first).firstWhere(
      (t) => t.title == 'Neon Rain',
    );
    final file = File(p.join(music, 'neon_rain.m4a'));
    final bytes = await file.readAsBytes();
    await file.delete();
    await scanner.scan();

    await file.writeAsBytes(bytes);
    await scanner.scan();

    final after = (await repo.watchTracks().first).firstWhere(
      (t) => t.title == 'Neon Rain',
    );
    expect(after.id, before.id);
  });

  test('the same song in two places is one track', () async {
    await File(p.join(music, 'neon_rain.m4a'))
        .copy(p.join(music, 'album', 'neon_rain_copy.m4a'));

    await scanner.scan();

    final tracks = await repo.watchTracks().first;
    expect(tracks.where((t) => t.title == 'Neon Rain'), hasLength(1));
    expect(await db.select(db.trackFiles).get(), hasLength(5));
  });

  test('the download folder is always scanned', () async {
    await Directory(downloads).create();
    await File(p.join(music, 'black_ice.mp3'))
        .copy(p.join(downloads, 'downloaded.mp3'));
    await (db.delete(db.libraryFolders)).go();

    await scanner.scan();

    final files = await db.select(db.trackFiles).get();
    expect(files.single.path, p.join(downloads, 'downloaded.mp3'));
    expect(files.single.folderId, isNull);
  });

  test('disabling or removing a folder hides its music', () async {
    await scanner.scan();
    final folder = (await db.select(db.libraryFolders).get()).single;

    await repo.setFolderEnabled(folder.id, enabled: false);
    await scanner.scan();
    expect(await repo.watchTracks().first, isEmpty);

    await repo.setFolderEnabled(folder.id, enabled: true);
    await scanner.scan();
    expect(await repo.watchTracks().first, hasLength(4));

    await repo.removeFolder(folder.id);
    expect(await repo.watchTracks().first, isEmpty);
    expect(Directory(music).listSync(), isNotEmpty); // files untouched
  });

  test('adding the same folder twice is ignored', () async {
    expect(await repo.addFolder(music), isFalse);
    expect(await repo.addFolder('$music/'), isFalse);
    expect(await db.select(db.libraryFolders).get(), hasLength(1));
  });

  test('reports progress up to the total', () async {
    final events = <ScanProgress>[];
    await scanner.scan(onProgress: events.add);

    expect(events.first.phase, ScanPhase.discovering);
    final last = events.lastWhere((e) => e.phase == ScanPhase.reading);
    expect(last.done, last.total);
    expect(last.total, 4);
  });

  test('unchanged rows are not rewritten (sync timestamps stay)', () async {
    await scanner.scan();
    final before = await db.select(db.tracks).get();
    await scanner.scan();
    final after = await db.select(db.tracks).get();
    expect(
      after.map((t) => t.updatedAt).toList(),
      before.map((t) => t.updatedAt).toList(),
    );
    expect(await db.select(db.tracks).get(), hasLength(4));
    expect(
      await (db.select(db.tracks)..where((t) => t.deleted.equals(true))).get(),
      isEmpty,
    );
  });
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(recursive: true)) {
    final target = p.join(to.path, p.relative(entity.path, from: from.path));
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}
