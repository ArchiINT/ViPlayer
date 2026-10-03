import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/library/cover_store.dart';
import 'package:viplayer/core/library/library_repository.dart';
import 'package:viplayer/core/library/library_scanner.dart';
import 'package:viplayer/core/sync/peer_store.dart';
import 'package:viplayer/core/sync/sync_service.dart';

/// A complete device: database, music folder, scanner and sync service.
class _Device {
  _Device._(this.db, this.dir, this.scanner, this.sync);

  final AppDatabase db;
  final Directory dir;
  final LibraryScanner scanner;
  final SyncService sync;

  String get music => p.join(dir.path, 'music');

  static Future<_Device> create(
    String id,
    DeviceKind kind,
    SharedPreferences prefs,
  ) async {
    final dir = await Directory.systemTemp.createTemp('vp_sync_$id');
    final db = AppDatabase(NativeDatabase.memory());
    final covers = p.join(dir.path, 'covers');
    await Directory(covers).create();
    final scanner = LibraryScanner(
      db,
      coversDir: covers,
      downloadDir: p.join(dir.path, 'music'),
    );
    final sync = SyncService(
      db: db,
      store: PeerStore(prefs),
      deviceId: id,
      kind: kind,
      deviceName: id.toUpperCase(),
      downloadDirectory: p.join(dir.path, 'music'),
      importFile: scanner.importFile,
      enableDiscovery: false,
      httpPort: 0, // any free port: two devices in one process
    );
    await sync.start();
    return _Device._(db, dir, scanner, sync);
  }

  Future<void> addMusic(List<String> fixtures) async {
    await Directory(music).create(recursive: true);
    for (final f in fixtures) {
      await File(f).copy(p.join(music, p.basename(f)));
    }
    await scanner.scan();
  }

  Future<List<String>> titles() async => [
    for (final t in await LibraryRepository(
      db,
      const CoverStore('/'),
    ).watchTracks().first)
      t.title,
  ]..sort();

  Future<void> dispose() async {
    await sync.dispose();
    await db.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  late _Device pc;
  late _Device phone;

  setUp(() async {
    // Separate settings per device (pairings live there).
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    pc = await _Device.create('pc', DeviceKind.desktop, prefs);
    phone = await _Device.create(
      'phone',
      DeviceKind.phone,
      _IsolatedPrefs(prefs),
    );
  });
  tearDown(() async {
    await pc.dispose();
    await phone.dispose();
  });

  /// Phone pairs with the PC: the PC shows a code, it is typed on the phone.
  Future<void> pair() async {
    await phone.sync.connect('127.0.0.1', pc.sync.port!);
    await phone.sync.requestPairing('pc');
    final code = pc.sync.snapshot.value.pendingCode!.code;
    await phone.sync.confirmPairing('pc', code);
    await pc.sync.connect('127.0.0.1', phone.sync.port!);
  }

  test('pairing: wrong code refused, right code pairs both sides', () async {
    await phone.sync.connect('127.0.0.1', pc.sync.port!);
    await phone.sync.requestPairing('pc');
    final code = pc.sync.snapshot.value.pendingCode!.code;
    final wrong = code == '000000' ? '111111' : '000000';

    await expectLater(
      phone.sync.confirmPairing('pc', wrong),
      throwsA(isA<SyncException>()),
    );
    expect(phone.sync.snapshot.value.paired, isEmpty);

    await phone.sync.confirmPairing('pc', code);
    expect(phone.sync.snapshot.value.paired.keys, ['pc']);
    expect(pc.sync.snapshot.value.paired.keys, ['phone']);
    expect(pc.sync.snapshot.value.pendingCode, isNull);
  });

  test('unpaired requests are rejected', () async {
    final client = HttpClient();
    final request = await client.get(
      '127.0.0.1',
      pc.sync.port!,
      '/changes?since=0',
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('metadata syncs both ways, files go phone -> PC', () async {
    await phone.addMusic(['test/fixtures/audio/black_ice.mp3']);
    await pc.addMusic(['test/fixtures/audio/neon_rain.m4a']);
    await pair();

    // Each side fetches its own files when it runs a sync; in the app both
    // do (on discovery). Simulate both.
    await phone.sync.syncWith('pc');
    await pc.sync.syncWith('phone');

    // The PC got the phone's file and has it in its library.
    expect(await pc.titles(), ['Neon Rain', 'Чёрный лёд']);
    expect(
      File(p.join(pc.music, 'Кибер Волна - Чёрный лёд.mp3')).existsSync(),
      isTrue,
    );
    // The phone knows the PC's track (metadata) but did not copy the file:
    // it is not liked or in an offline playlist.
    expect(await phone.titles(), ['Чёрный лёд']);
    final phoneTracks = await phone.db.select(phone.db.tracks).get();
    expect(phoneTracks.map((t) => t.title), contains('Neon Rain'));
  });

  test('the phone gets liked tracks from the PC', () async {
    await pc.addMusic(['test/fixtures/audio/neon_rain.m4a']);
    await pair();
    await phone.sync.syncWith('pc'); // metadata
    await (phone.db.update(phone.db.tracks)).write(
      TracksCompanion(
        liked: const Value(true),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    await phone.sync.syncWith('pc');

    expect(await phone.titles(), ['Neon Rain']);
    // And the like reached the PC.
    expect((await pc.db.select(pc.db.tracks).getSingle()).liked, isTrue);
  });
}

/// SharedPreferences view with its own key space, so two "devices" in one
/// test process do not share pairings.
class _IsolatedPrefs implements SharedPreferences {
  _IsolatedPrefs(this._inner);
  final SharedPreferences _inner;
  static const _prefix = 'phone.';

  @override
  String? getString(String key) => _inner.getString('$_prefix$key');
  @override
  Future<bool> setString(String key, String value) =>
      _inner.setString('$_prefix$key', value);
  @override
  bool? getBool(String key) => _inner.getBool('$_prefix$key');
  @override
  Future<bool> setBool(String key, bool value) =>
      _inner.setBool('$_prefix$key', value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
