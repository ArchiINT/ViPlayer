import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A small error log on disk, for diagnosing problems on the user's device
/// (`<support>/logs/viplayer.log`, rotated at 1 MB, previous kept as `.1`).
///
/// Only errors and a few lifecycle events are written — no library contents,
/// no listening history.
abstract final class AppLog {
  static const _maxBytes = 1024 * 1024;
  static File? _file;

  /// Path of the current log file (null before [init]).
  static String? get path => _file?.path;

  static Future<void> init(String supportDirectory) async {
    final dir = Directory(p.join(supportDirectory, 'logs'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'viplayer.log'));
    if (file.existsSync() && file.lengthSync() > _maxBytes) {
      await file.rename('${file.path}.1');
    }
    _file = File(p.join(dir.path, 'viplayer.log'));
    info('started (${Platform.operatingSystem})');
  }

  static void info(String message) => _write('INFO', message);

  static void error(String context, Object error, [StackTrace? stack]) {
    final trace = stack == null ? '' : '\n$stack';
    _write('ERROR', '$context: $error$trace');
  }

  static void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} $level $message';
    debugPrint(line);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // Logging must never break the app.
    }
  }
}
