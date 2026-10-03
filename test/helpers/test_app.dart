import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/app.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/download/download_providers.dart';
import 'package:viplayer/core/library/library_providers.dart';
import 'package:viplayer/core/library/library_scanner.dart';
import 'package:viplayer/core/platform/app_directories.dart';
import 'package:viplayer/core/player/player_providers.dart';
import 'package:viplayer/core/player/player_service.dart';
import 'package:viplayer/core/settings/settings_providers.dart';

import 'fake_audio_backend.dart';

/// Scanner stand-in for widget tests: the real one touches the file system
/// and spawns isolates, which widget tests' fake clock cannot drive.
class FakeLibraryScanner extends LibraryScanner {
  FakeLibraryScanner(super.db)
    : super(coversDir: '/tmp/covers', downloadDir: '/tmp/downloads');

  int scans = 0;

  @override
  Future<ScanResult> scan({
    bool includeDeviceMusic = false,
    void Function(ScanProgress)? onProgress,
  }) async {
    scans++;
    return const ScanResult(
      added: 0,
      updated: 0,
      removed: 0,
      totalFiles: 0,
      directories: [],
    );
  }
}

class TestApp {
  TestApp._(this.db, this.prefs, this.scanner, this.backend)
    : player = PlayerService(backend, prefs);

  final AppDatabase db;
  final SharedPreferences prefs;
  final FakeLibraryScanner scanner;
  final FakeAudioBackend backend;
  final PlayerService player;

  static Future<TestApp> create({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    // Synchronous stream closing keeps drift from leaving timers behind,
    // which widget tests' fake clock would wait on forever.
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    return TestApp._(
      db,
      await SharedPreferences.getInstance(),
      FakeLibraryScanner(db),
      FakeAudioBackend(),
    );
  }

  /// Extra provider overrides for a single test.
  List<Override> extraOverrides = [];

  Future<void> pump(WidgetTester tester) async {
    await pumpNoSettle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pumpNoSettle(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDirectoriesProvider.overrideWithValue(
            const AppDirectories(
              support: '/tmp/support',
              downloads: '/tmp/downloads',
            ),
          ),
          appDatabaseProvider.overrideWithValue(db),
          libraryScannerProvider.overrideWithValue(scanner),
          playerServiceProvider.overrideWithValue(player),
          // No real yt-dlp processes in widget tests.
          ytDlpProvider.overrideWithValue(null),
          ...extraOverrides,
        ],
        child: const ViPlayerApp(),
      ),
    );
  }

  /// Unmounts the app and closes the database so drift's stream timers do
  /// not outlive the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Real async: closing streams must not wait on the fake test clock.
    await tester.runAsync(player.dispose);
    await tester.runAsync(db.close);
  }

  /// Inserts a track with a local file, as a scan would.
  Future<void> addTrack({
    required String id,
    required String title,
    String artist = '',
    String album = '',
    int? trackNumber,
  }) async {
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            id: id,
            updatedAt: 1,
            fingerprint: 'fp-$id',
            title: title,
            artist: Value(artist),
            album: Value(album),
            trackNumber: Value(trackNumber),
            durationMs: const Value(185000),
            addedAt: 1,
          ),
        );
    await db
        .into(db.trackFiles)
        .insert(
          TrackFilesCompanion.insert(
            trackId: id,
            path: '/music/$id.m4a',
            sizeBytes: 1,
            modifiedAt: 1,
          ),
        );
  }
}
