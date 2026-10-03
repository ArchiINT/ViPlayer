import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viplayer/main.dart' as app;

/// Frame-timing test for the library: swipes between tabs and scrolls long
/// lists on the real app (real database, real covers) in profile mode.
///
/// Run with scripts/perf-test.sh, which points the app at a generated
/// library and prints the timeline summary.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Real vsync-driven frames, like a user would see — not test-pumped ones.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('library: tab swipes and scrolling', (tester) async {
    unawaited(app.main());
    // Startup + initial scan of the test library.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final pages = find.byType(TabBarView);
    expect(pages, findsOneWidget, reason: 'library should not be empty');

    await binding.traceAction(() async {
      // Swipe Tracks -> Albums -> Artists and back, twice.
      for (var round = 0; round < 2; round++) {
        for (final dx in [-600.0, -600.0, 600.0, 600.0]) {
          await tester.fling(pages, Offset(dx, 0), 1500);
          await tester.pumpAndSettle();
        }
      }

      // Scroll the tracks list down and up.
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, -900), 3000);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, 900), 3000);
        await tester.pumpAndSettle();
      }

      // Albums grid.
      await tester.fling(pages, const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      final grid = find.byType(GridView);
      for (var i = 0; i < 3; i++) {
        await tester.fling(grid, const Offset(0, -900), 3000);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'library');
  });
}
