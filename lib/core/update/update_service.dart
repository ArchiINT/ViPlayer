import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../platform/app_log.dart';
import '../sync/sync_service.dart';
import 'update_offer.dart';

enum UpdatePhase { none, downloading, ready, failed }

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.none,
    this.offer,
    this.progress = 0,
  });

  final UpdatePhase phase;

  /// The build being downloaded or ready to install.
  final UpdateOffer? offer;

  /// 0..1 while downloading.
  final double progress;
}

/// Result of "check for updates" in the settings.
enum UpdateCheck { noPeers, upToDate, downloading, ready, failed }

enum InstallResult { started, needsPermission, failed }

/// The Android side: own build number and the system installer.
abstract interface class UpdateInstaller {
  Future<int?> currentVersionCode();

  /// Opens the system installer for [apkPath]; the user confirms there.
  Future<InstallResult> install(String apkPath);
}

class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();

  static const _channel = MethodChannel('viplayer/update');

  @override
  Future<int?> currentVersionCode() =>
      _channel.invokeMethod<int>('versionCode');

  @override
  Future<InstallResult> install(String apkPath) async {
    final result = await _channel.invokeMethod<String>('install', {
      'path': apkPath,
    });
    return switch (result) {
      'ok' => InstallResult.started,
      'needPermission' => InstallResult.needsPermission,
      _ => InstallResult.failed,
    };
  }
}

/// Phone app updates over the LAN, as in Finanz: after each sync with a
/// paired PC it asks which build the PC offers (signed answer, see
/// SyncService.fetchUpdateOffer), downloads a newer APK in the background
/// (checked against the signed SHA-256) and, when the user taps "Install",
/// backs up the database and hands the APK to the Android installer.
///
/// Android installs it as an update (data kept) only if it is signed with
/// the same key and has a higher build number; otherwise the installer
/// refuses and nothing changes.
class UpdateService {
  UpdateService({
    required SyncService sync,
    required this.cacheDirectory,
    required this._installer,
    this._backup,
  }) : _sync = sync {
    _subscription = sync.synced.listen((peer) => unawaited(check(peer)));
  }

  final SyncService _sync;
  final UpdateInstaller _installer;
  final Future<void> Function()? _backup;

  /// Where downloaded APKs wait (shared with the installer via FileProvider:
  /// `<cache>/update/`, see res/xml/update_paths.xml).
  final String cacheDirectory;

  late final StreamSubscription<String> _subscription;
  final _state = ValueNotifier(const UpdateState());
  ValueListenable<UpdateState> get state => _state;
  File? _apk;

  /// Looks for a newer build at [peerId] and downloads it. Safe to call
  /// often: does nothing while downloading or when already downloaded.
  Future<void> check(String peerId) async {
    if (_state.value.phase == UpdatePhase.downloading) return;
    try {
      final offer = await _sync.fetchUpdateOffer(peerId);
      final own = await _installer.currentVersionCode();
      if (offer == null || own == null || offer.versionCode <= own) {
        await _clean();
        _state.value = const UpdateState();
        return;
      }
      final current = _state.value;
      if (current.phase == UpdatePhase.ready &&
          current.offer?.versionCode == offer.versionCode) {
        return;
      }
      _state.value = UpdateState(phase: UpdatePhase.downloading, offer: offer);
      await _clean();
      final apk = File(
        p.join(cacheDirectory, 'viplayer-${offer.versionCode}.apk'),
      );
      await _sync.downloadUpdate(
        peerId,
        offer,
        apk,
        onProgress: (f) => _state.value = UpdateState(
          phase: UpdatePhase.downloading,
          offer: offer,
          progress: f,
        ),
      );
      _apk = apk;
      _state.value = UpdateState(phase: UpdatePhase.ready, offer: offer);
    } catch (e, stack) {
      AppLog.error('app update from $peerId', e, stack);
      _state.value = UpdateState(
        phase: UpdatePhase.failed,
        offer: _state.value.offer,
      );
    }
  }

  /// Checks every paired PC on the network now (settings button).
  Future<UpdateCheck> checkNow() async {
    final s = _sync.snapshot.value;
    final peers = [
      for (final id in s.paired.keys)
        if (s.nearby.containsKey(id)) id,
    ];
    if (peers.isEmpty) return UpdateCheck.noPeers;
    for (final id in peers) {
      await check(id);
      if (_state.value.phase == UpdatePhase.ready) break;
    }
    return switch (_state.value.phase) {
      UpdatePhase.none => UpdateCheck.upToDate,
      UpdatePhase.downloading => UpdateCheck.downloading,
      UpdatePhase.ready => UpdateCheck.ready,
      UpdatePhase.failed => UpdateCheck.failed,
    };
  }

  /// Backs up the library database, then opens the system installer.
  Future<InstallResult> install() async {
    final apk = _apk;
    if (apk == null || !apk.existsSync()) return InstallResult.failed;
    try {
      await _backup?.call();
    } catch (e, stack) {
      // A failed backup must not block the update; the data stays in place.
      AppLog.error('backup before update', e, stack);
    }
    return _installer.install(apk.path);
  }

  Future<void> _clean() async {
    _apk = null;
    final dir = Directory(cacheDirectory);
    if (!dir.existsSync()) return;
    await for (final f in dir.list()) {
      try {
        await f.delete(recursive: true);
      } on FileSystemException {
        // In use or already gone: harmless.
      }
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _state.dispose();
  }
}
