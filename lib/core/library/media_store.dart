import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_files.dart';

/// Android only: the device's music as indexed by MediaStore.
/// Native side: android/app/src/main/kotlin/.../MediaStoreChannel.kt
class MediaStore {
  const MediaStore();

  static const _channel = MethodChannel('viplayer/media_store');

  static bool get isSupported => Platform.isAndroid;

  /// Asks for permission to read music if needed. Android 13+ uses
  /// READ_MEDIA_AUDIO ([Permission.audio]); older versions use storage.
  Future<bool> ensurePermission() async {
    if (!isSupported) return false;
    if (await Permission.audio.isGranted ||
        await Permission.storage.isGranted) {
      return true;
    }
    final results = await [Permission.audio, Permission.storage].request();
    return results.values.any((s) => s.isGranted || s.isLimited);
  }

  /// Audio files known to MediaStore. Empty without permission.
  Future<List<FoundFile>> listAudio() async {
    if (!isSupported || !await ensurePermission()) return const [];
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listAudio',
    );
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        if (isAudioPath(m['path']! as String))
          FoundFile(
            path: m['path']! as String,
            sizeBytes: (m['size']! as num).toInt(),
            modifiedMs: (m['modified']! as num).toInt(),
          ),
    ];
  }
}
