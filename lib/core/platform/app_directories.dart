import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_paths.dart';

/// Directories resolved once at startup (some lookups are async) and then
/// available synchronously everywhere.
class AppDirectories {
  const AppDirectories({
    required this.support,
    required this.downloads,
    required this.cache,
  });

  /// App-private, survives updates (Linux: ~/.local/share/com.viplayer.app).
  final String support;

  /// Temporary files the OS may delete (download previews).
  final String cache;

  /// Shared music folder for downloads — see [AppPaths.downloadDirectory].
  final String downloads;

  /// Extracted cover art, named by content hash. Kept in [support] rather than
  /// a cache dir so the OS never deletes covers the database refers to.
  String get covers => p.join(support, 'covers');

  /// Download previews (throwaway, emptied at startup).
  String get previews => p.join(cache, 'previews');

  static Future<AppDirectories> resolve() async {
    final support = (await getApplicationSupportDirectory()).path;
    final dirs = AppDirectories(
      support: support,
      downloads: AppPaths.downloadDirectory(),
      cache: (await getApplicationCacheDirectory()).path,
    );
    await Directory(dirs.covers).create(recursive: true);
    return dirs;
  }
}

/// Overridden in main() with the resolved value.
final appDirectoriesProvider = Provider<AppDirectories>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);
