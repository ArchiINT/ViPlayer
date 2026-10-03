import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../platform/app_directories.dart';
import 'collections_repository.dart';
import 'cover_store.dart';
import 'library_models.dart';
import 'library_providers.dart';

final collectionsRepositoryProvider = Provider<CollectionsRepository>(
  (ref) => CollectionsRepository(
    ref.watch(appDatabaseProvider),
    CoverStore(ref.watch(appDirectoriesProvider).covers),
  ),
);

/// All playlists, newest first.
final playlistsProvider = StreamProvider<List<PlaylistSummary>>(
  (ref) => ref.watch(collectionsRepositoryProvider).watchPlaylists(),
);

final playlistProvider = Provider.family<PlaylistSummary?, String>(
  (ref, id) =>
      ref.watch(playlistsProvider).value?.where((p) => p.id == id).firstOrNull,
);

final playlistItemsProvider = StreamProvider.family<List<PlaylistItem>, String>(
  (ref, id) => ref.watch(collectionsRepositoryProvider).watchPlaylistItems(id),
);

/// Liked tracks on this device, most recently liked first.
final likedTracksProvider = Provider<List<LibraryTrack>>((ref) {
  final tracks = ref.watch(libraryIndexProvider).value?.tracks ?? const [];
  return [
    for (final t in tracks)
      if (t.liked) t,
  ]..sort((a, b) => (b.likedAt ?? 0).compareTo(a.likedAt ?? 0));
});

final recentlyPlayedProvider = StreamProvider<List<LibraryTrack>>(
  (ref) => ref.watch(collectionsRepositoryProvider).watchRecentlyPlayed(),
);
