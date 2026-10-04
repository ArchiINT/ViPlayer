import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../download/download_models.dart';
import '../download/download_providers.dart';
import '../download/download_queue.dart';
import '../download/download_service.dart';
import '../library/library_models.dart';
import '../library/library_providers.dart';
import '../platform/app_directories.dart';
import '../platform/app_log.dart';
import '../platform/device_id.dart';
import '../settings/settings_providers.dart';
import 'peer_store.dart';
import 'sync_service.dart';

final peerStoreProvider = Provider<PeerStore>(
  (ref) => PeerStore(ref.watch(sharedPreferencesProvider)),
);

final thisDeviceKind = Platform.isAndroid
    ? DeviceKind.phone
    : DeviceKind.desktop;

/// Default name shown to other devices (editable in Settings → Sync).
String defaultDeviceName() => Platform.isAndroid
    ? 'Android'
    : Platform.localHostname.isEmpty
    ? 'PC'
    : Platform.localHostname;

final syncServiceProvider = Provider<SyncService>((ref) {
  final store = ref.watch(peerStoreProvider);
  final scanner = ref.watch(libraryScannerProvider);
  final service = SyncService(
    db: ref.watch(appDatabaseProvider),
    store: store,
    deviceId: ref.watch(deviceIdProvider),
    kind: thisDeviceKind,
    deviceName: store.deviceName ?? defaultDeviceName(),
    downloadDirectory: ref.watch(appDirectoriesProvider).downloads,
    coversDirectory: ref.watch(appDirectoriesProvider).covers,
    importFile: scanner.importFile,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Desktop side of "download through the PC": phone requests go into this
/// device's normal download queue.
class _QueueRemoteDownloads implements RemoteDownloads {
  _QueueRemoteDownloads(this._queue, this._service);

  final DownloadQueue _queue;
  final DownloadService _service;

  @override
  Future<void> enqueue(List<DownloadCandidate> items) async =>
      _queue.enqueue(items);

  @override
  Future<PreviewStream> preview(DownloadCandidate candidate) =>
      _service.preview(candidate);
}

/// Starts LAN sync once (watched by the app shell). Never fatal.
final syncBootstrapProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(syncServiceProvider);
  if (thisDeviceKind == DeviceKind.desktop) {
    service.remoteDownloads = _QueueRemoteDownloads(
      ref.read(downloadQueueProvider),
      ref.read(downloadServiceProvider),
    );
  }
  try {
    if (Platform.isAndroid) {
      await const MethodChannel('viplayer/network')
          .invokeMethod<void>('acquireMulticastLock');
    }
    await service.start();
  } catch (e) {
    AppLog.error('LAN sync unavailable', e);
  }
});

final syncSnapshotProvider =
    NotifierProvider<SyncSnapshotNotifier, SyncSnapshot>(
      SyncSnapshotNotifier.new,
    );

class SyncSnapshotNotifier extends Notifier<SyncSnapshot> {
  @override
  SyncSnapshot build() {
    final snapshot = ref.watch(syncServiceProvider).snapshot;
    void listener() => state = snapshot.value;
    snapshot.addListener(listener);
    ref.onDispose(() => snapshot.removeListener(listener));
    return snapshot.value;
  }
}

/// Tracks that are not on this device but can be streamed from a paired
/// device on the network right now ("at home"). Their path and cover are
/// stream URLs.
///
/// Rebuilt only when the set of online peers or their file lists change —
/// not on every discovery beacon.
final remoteTracksProvider = StreamProvider<List<LibraryTrack>>((ref) {
  final key = ref.watch(
    syncSnapshotProvider.select((s) {
      final online = [
        for (final MapEntry(key: id, value: files) in s.remoteFiles.entries)
          if (s.nearby.containsKey(id) && s.paired.containsKey(id))
            '$id:${identityHashCode(files)}',
      ]..sort();
      return online.join(',');
    }),
  );
  if (key.isEmpty) return Stream.value(const []);

  final service = ref.read(syncServiceProvider);
  final db = ref.watch(appDatabaseProvider);
  final ids = {
    for (final MapEntry(key: peer, value: files)
        in service.snapshot.value.remoteFiles.entries)
      if (key.contains(peer)) ...files,
  }.toList();
  if (ids.isEmpty) return Stream.value(const []);

  return db
      .customSelect(
        'SELECT * FROM tracks t WHERE t.deleted = 0 '
        'AND NOT EXISTS (SELECT 1 FROM track_files f WHERE f.track_id = t.id) '
        'AND t.id IN (${List.filled(ids.length, '?').join(', ')})',
        variables: [for (final id in ids) Variable.withString(id)],
        readsFrom: {db.tracks, db.trackFiles},
      )
      .watch()
      .map((rows) {
        final tracks = <LibraryTrack>[];
        for (final row in rows) {
          final t = db.tracks.map(row.data);
          final url = service.streamUrl(t.id);
          if (url == null) continue;
          tracks.add(
            LibraryTrack(
              id: t.id,
              title: t.title,
              artist: t.artist,
              album: t.album,
              albumArtist: t.albumArtist,
              durationMs: t.durationMs,
              trackNumber: t.trackNumber,
              discNumber: t.discNumber,
              year: t.year,
              genre: t.genre,
              liked: t.liked,
              likedAt: t.likedAt,
              addedAt: t.addedAt,
              path: url,
              coverPath: service.coverUrl(t.id),
            ),
          );
        }
        return tracks;
      });
});
