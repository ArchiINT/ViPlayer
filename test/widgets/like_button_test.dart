import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/library/collections_providers.dart';
import 'package:viplayer/core/library/collections_repository.dart';
import 'package:viplayer/core/library/cover_store.dart';
import 'package:viplayer/core/library/library_models.dart';
import 'package:viplayer/l10n/generated/app_localizations.dart';
import 'package:viplayer/shared/widgets/like_button.dart';

/// Saves only when the test says so.
class _SlowRepository extends CollectionsRepository {
  _SlowRepository(AppDatabase db) : super(db, const CoverStore('/tmp'));

  final saves = <bool>[];
  var _done = Completer<void>();

  void finishSave() => _done.complete();
  void failSave() => _done.completeError(StateError('disk full'));

  @override
  Future<void> setLiked(String trackId, {required bool liked}) {
    saves.add(liked);
    _done = Completer<void>();
    return _done.future;
  }
}

LibraryTrack _track({bool liked = false}) => LibraryTrack(
  id: 't1',
  title: 'Song',
  artist: 'Artist',
  album: '',
  durationMs: 180000,
  liked: liked,
  addedAt: 0,
  path: '/music/song.mp3',
);

void main() {
  late AppDatabase db;
  late _SlowRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = _SlowRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, LibraryTrack track) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: LikeButton(track: track)),
          ),
        ),
      );

  testWidgets('the heart fills at once, before the save lands', (tester) async {
    await pump(tester, _track());
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(repository.saves, [true]);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // The library confirms it: still liked, nothing pending.
    repository.finishSave();
    await pump(tester, _track(liked: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('a failed save reverts the heart', (tester) async {
    await pump(tester, _track());
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    repository.failSave();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });
}
