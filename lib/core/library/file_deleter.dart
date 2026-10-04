import 'dart:io';

import 'package:flutter/services.dart';

/// Deletes audio files from disk.
///
/// Desktop: plain file deletion. Android: files this app created can be
/// deleted directly; files saved by other apps (Telegram, …) need the user's
/// confirmation through the system MediaStore dialog (Android 11+ rule).
class FileDeleter {
  const FileDeleter();

  static const _channel = MethodChannel('viplayer/media_store');

  /// Deletes [paths]. Returns false if the user declined the system dialog
  /// or a file could not be removed; files already gone count as deleted.
  Future<bool> delete(List<String> paths) async {
    final blocked = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        await file.delete();
      } on FileSystemException {
        blocked.add(path);
      }
    }
    if (blocked.isEmpty) return true;
    if (!Platform.isAndroid) return false;
    final ok = await _channel.invokeMethod<bool>('deleteFiles', {
      'paths': blocked,
    });
    return ok ?? false;
  }
}
