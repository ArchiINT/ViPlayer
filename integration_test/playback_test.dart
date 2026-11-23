import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viplayer/core/player/player_providers.dart';
import 'package:viplayer/core/player/player_service.dart';
import 'package:viplayer/main.dart' as app;
import 'package:viplayer/shared/widgets/track_tile.dart';

/// End-to-end playback through the real engine (libmpv): tap a track, check
/// that time advances, skip to the next one. Volume is muted first.
///
/// Run with scripts/playback-test.sh, which points the app at a test library
/// and a throwaway data directory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays a track through the real engine', (tester) async {
    unawaited(app.main());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final player = container.read(playerServiceProvider);
    await player.setVolume(0);

    final tiles = find.byType(TrackTile);
    expect(tiles, findsWidgets, reason: 'test library must not be empty');
    await tester.tap(tiles.first);

    // Let real time pass while the engine plays.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    final snapshot = player.snapshot.value;
    expect(snapshot.playing, isTrue);
    expect(snapshot.duration, greaterThan(Duration.zero));
    expect(
      player.currentPosition,
      greaterThan(const Duration(milliseconds: 800)),
    );

    final first = snapshot.current!.id;
    await player.next();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    expect(player.snapshot.value.current!.id, isNot(first));

    // The endless queue, with the engine reporting changes asynchronously.
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pump();
    }

    int upNext() {
      final s = player.snapshot.value;
      return s.queue.length - s.index - 1;
    }

    await settle();
    expect(upNext(), PlayerService.upNextTarget);

    await player.toggleShuffle();
    await settle();
    expect(player.snapshot.value.shuffle, isTrue);
    expect(upNext(), PlayerService.upNextTarget);

    for (var i = 0; i < 5; i++) {
      await player.next();
    }
    await settle();
    expect(upNext(), PlayerService.upNextTarget);

    final s = player.snapshot.value;
    await player.removeAt(s.index + 1);
    await player.playNext(s.current!);
    await settle();
    expect(upNext(), PlayerService.upNextTarget + 1);

    // Tracks also end on their own (use test files of under 10 s).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 10)),
    );
    await tester.pump();
    expect(upNext(), PlayerService.upNextTarget);

    await player.pause();
  });
}
