import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'audio_files.dart';
import 'fingerprint.dart';
import 'media_store.dart';

enum ScanPhase { discovering, reading, saving }

class ScanProgress {
  const ScanProgress(this.phase, {this.done = 0, this.total = 0});

  final ScanPhase phase;
  final int done;
  final int total;

  /// 0..1, or null while the amount of work is still unknown.
  double? get fraction => total == 0 ? null : done / total;
}

class ScanResult {
  const ScanResult({
    required this.added,
    required this.updated,
    required this.removed,
    required this.totalFiles,
    required this.directories,
  });

  final int added;
  final int updated;
  final int removed;
  final int totalFiles;

  /// Directories visited, for the desktop folder watcher.
  final List<String> directories;

  bool get changedAnything => added + updated + removed > 0;
}

/// Synchronises the database with the audio files on this device.
///
/// Incremental: a file is (re)read only when it is new or its size/mtime
/// changed, so a rescan of an unchanged library takes well under a second.
/// Tag reading runs in parallel background isolates.
///
/// Sources: enabled library folders, the download folder and — on Android,
/// when enabled — MediaStore. A file found by several sources is one file.
///
/// Tracks themselves are never deleted here: they are synced metadata (likes,
/// playlists) and the song may still exist on another device. A track without
/// a local file is simply not shown in the local library.
class LibraryScanner {
  LibraryScanner(
    this._db, {
    required this.coversDir,
    required this.downloadDir,
    this.mediaStore = const MediaStore(),
  });

  final AppDatabase _db;
  final String coversDir;
  final String downloadDir;
  final MediaStore mediaStore;

  static const _batchSize = 48;

  /// Bump when tag reading changes (new fallbacks, cleanup rules): the next
  /// scan then re-reads every file once and updates tracks in place.
  static const readerVersion = 2;
  static const _readerVersionKey = 'scanner_reader_version';
  static const _uuid = Uuid();

  Future<ScanResult> scan({
    bool includeDeviceMusic = false,
    void Function(ScanProgress)? onProgress,
  }) async {
    onProgress?.call(const ScanProgress(ScanPhase.discovering));

    // 1. What is on disk now?
    final folders = await (_db.select(
      _db.libraryFolders,
    )..where((f) => f.enabled.equals(true))).get();
    final roots = [
      for (final f in folders) ScanRoot(f.path, folderId: f.id),
      ScanRoot(downloadDir),
    ];
    final discovery = await _discoverInIsolate(roots);
    final onDisk = {for (final f in discovery.files) f.path: f};
    if (includeDeviceMusic && MediaStore.isSupported) {
      for (final f in await mediaStore.listAudio()) {
        onDisk.putIfAbsent(f.path, () => f);
      }
    }

    // 2. Diff against what the database knows.
    final known = {
      for (final row in await _db.select(_db.trackFiles).get()) row.path: row,
    };
    final rereadAll = await _storedReaderVersion() < readerVersion;
    final toRead = <FoundFile>[];
    for (final file in onDisk.values) {
      final row = known[file.path];
      if (rereadAll ||
          row == null ||
          row.sizeBytes != file.sizeBytes ||
          row.modifiedAt != file.modifiedMs ||
          row.folderId != file.folderId) {
        toRead.add(file);
      }
    }
    final removedIds = [
      for (final row in known.values)
        if (!onDisk.containsKey(row.path)) row.id,
    ];

    // 3. Read tags in parallel isolates, save in batches as results arrive.
    var added = 0;
    var updated = 0;
    var done = 0;
    onProgress?.call(ScanProgress(ScanPhase.reading, total: toRead.length));

    final fingerprints = await _loadFingerprints();
    final batches = [
      for (var i = 0; i < toRead.length; i += _batchSize)
        toRead.sublist(i, math.min(i + _batchSize, toRead.length)),
    ];
    final parallelism = math.max(
      1,
      math.min(4, Platform.numberOfProcessors - 1),
    );

    for (var i = 0; i < batches.length; i += parallelism) {
      final group = batches.skip(i).take(parallelism);
      final results = await Future.wait([
        for (final batch in group) _readInIsolate(batch, coversDir),
      ]);
      for (final scanned in results) {
        final (a, u) = await _save(scanned, known, fingerprints);
        added += a;
        updated += u;
        done += scanned.length;
        onProgress?.call(
          ScanProgress(ScanPhase.reading, done: done, total: toRead.length),
        );
      }
    }

    // 4. Forget files that are gone.
    if (removedIds.isNotEmpty) {
      onProgress?.call(const ScanProgress(ScanPhase.saving));
      await _db.batch((b) {
        for (final id in removedIds) {
          b.deleteWhere(_db.trackFiles, (f) => f.id.equals(id));
        }
      });
    }

    if (rereadAll) await _storeReaderVersion();

    return ScanResult(
      added: added,
      updated: updated,
      removed: removedIds.length,
      totalFiles: onDisk.length,
      directories: discovery.directories,
    );
  }

  /// Adds one file (a fresh download) to the library without a full scan.
  /// Returns the id of its track.
  Future<String> importFile(String path, {int? folderId}) async {
    final stat = await File(path).stat();
    final found = FoundFile(
      path: path,
      sizeBytes: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      folderId: folderId,
    );
    final scanned = await _readInIsolate([found], coversDir);
    final known = {
      for (final row in await (_db.select(
        _db.trackFiles,
      )..where((f) => f.path.equals(path))).get())
        row.path: row,
    };
    await _save(scanned, known, await _loadFingerprints());
    final file = await (_db.select(
      _db.trackFiles,
    )..where((f) => f.path.equals(path))).getSingle();
    return file.trackId;
  }

  // Isolate entry points are static so their closures capture only the
  // arguments — a closure created inside an instance method could capture
  // `this` (and the database), which cannot be sent to another isolate.
  static Future<DiscoveryResult> _discoverInIsolate(List<ScanRoot> roots) =>
      Isolate.run(() => discoverAudioFiles(roots));

  static Future<List<ScannedFile>> _readInIsolate(
    List<FoundFile> batch,
    String coversDir,
  ) => Isolate.run(() => readAudioFiles(batch, coversDir));

  Future<int> _storedReaderVersion() async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.key.equals(_readerVersionKey))).getSingleOrNull();
    return row?.value ?? 1;
  }

  Future<void> _storeReaderVersion() => _db
      .into(_db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(key: _readerVersionKey, value: readerVersion),
      );

  /// fingerprint -> (track id, is tombstoned)
  Future<Map<String, ({String id, bool deleted})>> _loadFingerprints() async {
    final rows =
        await (_db.selectOnly(_db.tracks)..addColumns([
              _db.tracks.id,
              _db.tracks.fingerprint,
              _db.tracks.deleted,
            ]))
            .get();
    return {
      for (final r in rows)
        r.read(_db.tracks.fingerprint)!: (
          id: r.read(_db.tracks.id)!,
          deleted: r.read(_db.tracks.deleted)!,
        ),
    };
  }

  /// Writes one batch in a single transaction. Returns (added, updated) file
  /// counts.
  Future<(int, int)> _save(
    List<ScannedFile> scanned,
    Map<String, TrackFileRow> known,
    Map<String, ({String id, bool deleted})> fingerprints,
  ) async {
    var added = 0;
    var updated = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      for (final s in scanned) {
        final fingerprint = Fingerprint.fromMetadata(
          artist: s.artist,
          title: s.title,
          durationMs: s.durationMs,
        );
        final existing = fingerprints[fingerprint];
        final previous = known[s.file.path];
        final String trackId;

        if (existing == null && previous != null) {
          // The same file with different tags (edited, or read better now):
          // update its track instead of creating a new one, so likes,
          // playlists and history stay attached.
          trackId = previous.trackId;
          await (_db.update(
            _db.tracks,
          )..where((t) => t.id.equals(trackId))).write(
            TracksCompanion(
              updatedAt: Value(now),
              fingerprint: Value(fingerprint),
              title: Value(s.title),
              artist: Value(s.artist),
              album: Value(s.album),
              albumArtist: Value(s.albumArtist),
              durationMs: Value(s.durationMs),
              trackNumber: Value(s.trackNumber),
              discNumber: Value(s.discNumber),
              year: Value(s.year),
              genre: Value(s.genre),
            ),
          );
          fingerprints
            ..removeWhere((_, v) => v.id == trackId)
            ..[fingerprint] = (id: trackId, deleted: false);
        } else if (existing == null) {
          trackId = _uuid.v4();
          await _db
              .into(_db.tracks)
              .insert(
                TracksCompanion.insert(
                  id: trackId,
                  updatedAt: now,
                  fingerprint: fingerprint,
                  title: s.title,
                  artist: Value(s.artist),
                  album: Value(s.album),
                  albumArtist: Value(s.albumArtist),
                  durationMs: Value(s.durationMs),
                  trackNumber: Value(s.trackNumber),
                  discNumber: Value(s.discNumber),
                  year: Value(s.year),
                  genre: Value(s.genre),
                  addedAt: now,
                ),
              );
          fingerprints[fingerprint] = (id: trackId, deleted: false);
        } else {
          trackId = existing.id;
          // A file reappeared for a deleted track: bring the track back.
          if (existing.deleted) {
            await (_db.update(
              _db.tracks,
            )..where((t) => t.id.equals(trackId))).write(
              TracksCompanion(
                deleted: const Value(false),
                updatedAt: Value(now),
              ),
            );
            fingerprints[fingerprint] = (id: trackId, deleted: false);
          }
        }

        final file = TrackFilesCompanion.insert(
          trackId: trackId,
          path: s.file.path,
          sizeBytes: s.file.sizeBytes,
          modifiedAt: s.file.modifiedMs,
          coverId: Value(s.coverId),
          folderId: Value(s.file.folderId),
        );
        await _db
            .into(_db.trackFiles)
            .insert(
              file,
              onConflict: DoUpdate((_) => file, target: [_db.trackFiles.path]),
            );
        // A file is back for a track deleted here earlier: sync may bring
        // it again from now on.
        await (_db.delete(
          _db.excludedTracks,
        )..where((e) => e.trackId.equals(trackId))).go();
        known.containsKey(s.file.path) ? updated++ : added++;
      }
    });
    return (added, updated);
  }
}
