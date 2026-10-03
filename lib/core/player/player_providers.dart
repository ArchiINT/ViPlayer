import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/collections_providers.dart';
import '../library/library_models.dart';
import '../library/library_providers.dart';
import '../platform/device_id.dart';
import 'play_history_tracker.dart';
import 'player_service.dart';

/// Created in main() (it must exist before the system media controls start)
/// and injected via a ProviderScope override.
final playerServiceProvider = Provider<PlayerService>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Queue, current track, modes. Does not change with the position.
final playerSnapshotProvider =
    NotifierProvider<PlayerSnapshotNotifier, PlayerSnapshot>(
      PlayerSnapshotNotifier.new,
    );

class PlayerSnapshotNotifier extends Notifier<PlayerSnapshot> {
  @override
  PlayerSnapshot build() {
    final snapshot = ref.watch(playerServiceProvider).snapshot;
    void listener() => state = snapshot.value;
    snapshot.addListener(listener);
    ref.onDispose(() => snapshot.removeListener(listener));
    return snapshot.value;
  }
}

final currentTrackProvider = Provider<LibraryTrack?>(
  (ref) => ref.watch(playerSnapshotProvider.select((s) => s.current)),
);

/// Playback position, several updates per second — watch it only in small
/// widgets (seek bar, time labels).
final playerPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(playerServiceProvider).position,
);

/// Wires the player to the rest of the app. Watched once by the app shell:
///  * restores the last session as soon as the library is loaded;
///  * keeps queued tracks fresh when the library changes (likes, tags);
///  * stores the real track length when tags were wrong;
///  * records listening history.
final playerBootstrapProvider = Provider<void>((ref) {
  final player = ref.watch(playerServiceProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  final collections = ref.watch(collectionsRepositoryProvider);
  final deviceId = ref.watch(deviceIdProvider);

  final history = PlayHistoryTracker(
    player,
    (track, listened) => collections.recordPlay(
      trackId: track.id,
      listenedMs: listened.inMilliseconds,
      deviceId: deviceId,
    ),
  );
  ref.onDispose(history.dispose);

  player.onDurationMeasured = (track, actual) =>
      repository.updateDuration(track.id, actual.inMilliseconds);

  var restored = false;
  ref.listen(libraryTracksProvider, (_, next) {
    final tracks = next.value;
    if (tracks == null) return;
    final byPath = {for (final t in tracks) t.path: t};
    if (!restored) {
      restored = true;
      player.restoreSession(byPath);
    } else {
      player.refreshTracks(byPath);
    }
  }, fireImmediately: true);
});
