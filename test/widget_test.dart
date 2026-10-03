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

    // New playlist from the Playlists tab.
    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget); // its page
    expect(find.text('This playlist is empty'), findsOneWidget);

    // Back to the list: Liked shows 1 track, playlist is listed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget);
    await tester.tap(find.text('Liked'));
    await tester.pumpAndSettle();
    expect(find.text('Neon Rain'), findsOneWidget);

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
}
