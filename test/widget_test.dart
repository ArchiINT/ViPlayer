import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('starts on an empty library in English by default', (
    tester,
  ) async {
    final app = await TestApp.create();
    await app.pump(tester);

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(app.scanner.scans, 1, reason: 'library is refreshed on startup');

    await app.dispose(tester);
  });

  testWidgets('restores the saved language', (tester) async {
    final app = await TestApp.create(prefs: {'settings.language': 'ru'});
    await app.pump(tester);

    expect(find.text('Медиатека пуста'), findsOneWidget);

    await app.dispose(tester);
  });

  testWidgets('switching language in settings updates the UI and persists', (
    tester,
  ) async {
    final app = await TestApp.create();
    await app.pump(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RU'));
    await tester.pumpAndSettle();

    expect(find.text('Оформление'), findsOneWidget);
    expect(app.prefs.getString('settings.language'), 'ru');

    await app.dispose(tester);
  });

  testWidgets('library lists tracks, albums and artists', (tester) async {
    final app = await TestApp.create();
    await app.addTrack(
      id: 'a',
      title: 'Neon Rain',
      artist: 'Synth Rider',
      album: 'Night City',
      trackNumber: 1,
    );
    await app.addTrack(
      id: 'b',
      title: 'Ghost Signal',
      artist: 'Synth Rider',
      album: 'Night City',
      trackNumber: 2,
    );
    await app.pump(tester);

    expect(find.text('Neon Rain'), findsOneWidget);
    expect(find.text('2 tracks · 6 min'), findsOneWidget);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Night City'), findsOneWidget);

    await tester.tap(find.text('Night City'));
    await tester.pumpAndSettle();
    expect(find.text('Synth Rider'), findsWidgets);
    expect(find.text('1'), findsOneWidget); // track numbers on album page

    await app.dispose(tester);
  });

  testWidgets('search finds tracks by word prefix', (tester) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.addTrack(id: 'b', title: 'Чёрный лёд', artist: 'Кибер Волна');
    await app.pump(tester);

    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'чёр');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Чёрный лёд'), findsOneWidget);
    expect(find.text('Neon Rain'), findsNothing);

    await app.dispose(tester);
  });

  testWidgets('tapping a track plays it: mini player, then full player', (
    tester,
  ) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.addTrack(id: 'b', title: 'Ghost Signal', artist: 'Synth Rider');
    await app.pump(tester);

    // Sorted by title: Ghost Signal, Neon Rain.
    await tester.tap(find.text('Ghost Signal'));
    await tester.pumpAndSettle();

    expect(app.player.snapshot.value.current!.title, 'Ghost Signal');
    expect(app.backend.isPlaying, isTrue);
    expect(find.text('Ghost Signal'), findsNWidgets(2)); // list + mini player

    await tester.tap(find.byTooltip('Next').first);
    await tester.pumpAndSettle();
    expect(app.player.snapshot.value.current!.title, 'Neon Rain');

    await tester.tap(find.text('Neon Rain').last); // mini player
    await tester.pumpAndSettle();
    expect(find.text('Now playing'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(app.backend.isPlaying, isFalse);

    await app.dispose(tester);
  });
}
