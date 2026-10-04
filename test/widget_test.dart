import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/download/download_providers.dart';
import 'package:viplayer/core/download/download_service.dart';
import 'package:viplayer/core/download/tools/tagger.dart';
import 'package:viplayer/core/library/cover_store.dart';
import 'package:viplayer/core/library/library_repository.dart';

import 'helpers/test_app.dart';

/// Resolves any link to one fixed track and "downloads" it instantly.
class _FakeDownloads extends DownloadService {
  _FakeDownloads(LibraryRepository library)
    : super(
        client: http.Client(),
        downloadDirectory: '/tmp/none',
        library: library,
        importFile: (_) async => 'id',
        tagger: const DartTagger(),
      );

  static const track = DownloadCandidate(
    service: MusicService.soundcloud,
    sourceId: '1',
    sourceUrl: 'https://soundcloud.com/a/b',
    title: 'Backtoback',
    artist: 'angelrot',
    durationMs: 180000,
  );

  @override
  List<MusicService> get searchableServices => const [MusicService.soundcloud];

  @override
  Future<Map<MusicService, SearchOutcome>> search(
    String query, {
    List<MusicService>? services,
  }) async => {
    MusicService.soundcloud: const SearchOutcome([track]),
  };

  @override
  Future<PreviewStream> preview(DownloadCandidate c) async =>
      const PreviewStream('https://stream/1.mp3');

  @override
  Future<ResolvedLink> resolve(String text) async =>
      const ResolvedLink(service: MusicService.soundcloud, items: [track]);

  @override
  Future<String> download(
    DownloadCandidate c, {
    required DownloadFormat format,
    void Function(DownloadStage stage, double? progress)? onProgress,
    Completer<void>? cancel,
  }) async {
    onProgress?.call(DownloadStage.downloading, 0.5);
    return 'id';
  }
}

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

  testWidgets('library tabs: tracks, liked, playlists', (tester) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.addTrack(id: 'b', title: 'Ghost Signal', artist: 'Synth Rider');
    await app.pump(tester);

    expect(find.text('Neon Rain'), findsOneWidget);
    expect(find.text('2 tracks · 6 min'), findsOneWidget);
    expect(find.text('Albums'), findsNothing);
    expect(find.text('Artists'), findsNothing);

    await tester.tap(find.text('Liked'));
    await tester.pumpAndSettle();
    expect(find.text('No liked tracks yet'), findsOneWidget);

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.text('New playlist'), findsOneWidget);
    expect(find.text('Recently played'), findsOneWidget);

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

  testWidgets('create a playlist, like a track from its menu', (tester) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.pump(tester);

    // Like via the track menu (long press).
    await tester.longPress(find.text('Neon Rain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    final row = await tester.runAsync(
      () => app.db.select(app.db.tracks).getSingle(),
    );
    expect(row!.liked, isTrue);

    // Liked tab shows it.
    await tester.tap(find.text('Liked'));
    await tester.pumpAndSettle();
    expect(find.text('Neon Rain'), findsWidgets);

    // New playlist from the Playlists tab.
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget); // its page
    expect(find.text('This playlist is empty'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget);

    await app.dispose(tester);
  });

  testWidgets('delete a track from this device', (tester) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.pump(tester);

    await tester.longPress(find.text('Neon Rain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Neon Rain'), findsNothing);
    final excluded = await tester.runAsync(
      () => app.db.select(app.db.excludedTracks).get(),
    );
    expect(
      excluded!.single.trackId,
      'a',
      reason: 'sync will not bring it back',
    );

    await app.dispose(tester);
  });

  testWidgets('download by link: preview, download, see it done', (
    tester,
  ) async {
    final app = await TestApp.create();
    app.extraOverrides = [
      downloadServiceProvider.overrideWith(
        (ref) => _FakeDownloads(
          LibraryRepository(app.db, const CoverStore('/covers')),
        ),
      ),
    ];
    await app.pump(tester);

    await tester.tap(find.byIcon(Icons.download_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://soundcloud.com/a/b',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Backtoback'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text('angelrot — Backtoback'), findsOneWidget);
    expect(find.text('In your library'), findsOneWidget);

    await app.dispose(tester);
  });

  testWidgets('download by name: listen to a result, then pick it', (
    tester,
  ) async {
    final app = await TestApp.create();
    app.extraOverrides = [
      downloadServiceProvider.overrideWith(
        (ref) => _FakeDownloads(
          LibraryRepository(app.db, const CoverStore('/covers')),
        ),
      ),
    ];
    await app.pump(tester);

    await tester.tap(find.byIcon(Icons.download_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('By name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'backtoback');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Backtoback'), findsOneWidget);

    // Listen first.
    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();
    expect(app.previewBackend.opened, ['https://stream/1.mp3']);
    expect(find.byTooltip('Pause'), findsOneWidget);

    // Then pick and download.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download selected (1)'));
    await tester.pumpAndSettle();
    expect(find.text('In your library'), findsOneWidget);
    expect(app.preview.state.value.key, isNull, reason: 'preview stopped');

    await app.dispose(tester);
  });

  testWidgets('up next: add a track from the library to the queue', (
    tester,
  ) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'a', title: 'Neon Rain', artist: 'Synth Rider');
    await app.addTrack(id: 'b', title: 'Ghost Signal', artist: 'Synth Rider');
    await app.pump(tester);

    await tester.tap(find.text('Neon Rain'));
    await tester.pumpAndSettle();
    await app.player.playQueue([app.player.snapshot.value.current!]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Neon Rain').last); // mini player
    await tester.pumpAndSettle();
    expect(find.textContaining('Up next', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    // Sorted by title: Ghost Signal is the first row.
    await tester.tap(find.byTooltip('Play next').first);
    await tester.pumpAndSettle();

    expect(
      [for (final t in app.player.snapshot.value.queue) t.title],
      ['Neon Rain', 'Ghost Signal'],
    );

    await app.dispose(tester);
  });

  testWidgets('long recordings get their own tab; short ones can be hidden', (
    tester,
  ) async {
    final app = await TestApp.create();
    await app.addTrack(id: 'song', title: 'Neon Rain', durationMs: 185000);
    await app.addTrack(
      id: 'book',
      title: 'Master and Margarita',
      durationMs: 9 * 3600 * 1000,
    );
    await app.addTrack(id: 'clip', title: 'Ringtone', durationMs: 20000);
    await app.pump(tester);

    // Default: books from 20 min live in their own tab.
    expect(find.text('Master and Margarita'), findsNothing);
    expect(find.text('Ringtone'), findsOneWidget);
    await tester.tap(find.text('Books & podcasts'));
    await tester.pumpAndSettle();
    expect(find.text('Master and Margarita'), findsOneWidget);

    // Hide tracks shorter than 30 s.
    await app.prefs.setInt('settings.minTrackSeconds', 30);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide short tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shorter than 30 s').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();
    expect(find.text('Ringtone'), findsNothing);
    expect(find.text('Neon Rain'), findsOneWidget);

    await app.dispose(tester);
  });
}
