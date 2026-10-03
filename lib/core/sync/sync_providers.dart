import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../library/library_providers.dart';
import '../platform/app_directories.dart';
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
    importFile: scanner.importFile,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Starts LAN sync once (watched by the app shell). Never fatal.
final syncBootstrapProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(syncServiceProvider);
  try {
    if (Platform.isAndroid) {
      await const MethodChannel('viplayer/network')
          .invokeMethod<void>('acquireMulticastLock');
    }
    await service.start();
  } catch (e) {
    debugPrint('LAN sync unavailable: $e');
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
