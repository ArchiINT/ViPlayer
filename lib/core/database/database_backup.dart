import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_database.dart';

/// Writes a copy of the library database (likes, playlists, history) into
/// [directory] and keeps the newest [keep] copies. VACUUM INTO makes a
/// consistent snapshot while the app keeps running.
Future<File> backupDatabase(
  AppDatabase db,
  String directory, {
  String reason = 'backup',
  int keep = 3,
}) async {
  final dir = Directory(directory);
  await dir.create(recursive: true);
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file = File(p.join(directory, 'viplayer-$reason-$stamp.sqlite'));
  await db.customStatement('VACUUM INTO ?', [file.path]);

  final copies =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('viplayer-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // newest first
  for (final old in copies.skip(keep)) {
    await old.delete();
  }
  return file;
}
