import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/download/download_models.dart';
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
      coversDirectory: covers,
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

  test('connect by address explains what went wrong', () async {
    Future<SyncFailure?> failure(String host, int port) async {
      try {
        await phone.sync.connect(host, port);
        return null;
      } on SyncException catch (e) {
        return e.reason;
      }
    }

    // Nothing listens there.
    final closed = await ServerSocket.bind('127.0.0.1', 0);
    final freePort = closed.port;
    await closed.close();
    expect(await failure('127.0.0.1', freePort), SyncFailure.unreachable);

    // Some other HTTP server.
    final other = await HttpServer.bind('127.0.0.1', 0);
    other.listen(
      (r) => r.response
        ..write('<html>router</html>')
        ..close(),
    );
    expect(await failure('127.0.0.1', other.port), SyncFailure.notViPlayer);
    await other.close(force: true);

    expect(await failure('127.0.0.1', phone.sync.port!), SyncFailure.isSelf);
    expect(await failure('127.0.0.1', pc.sync.port!), isNull);
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

  test('the PC syncs back when only the phone can reach it', () async {
    // The phone's broadcasts never reach the PC (common with Wi-Fi):
    // the PC learns about the phone from its signed requests.
    await phone.addMusic(['test/fixtures/audio/black_ice.mp3']);
    await phone.sync.connect('127.0.0.1', pc.sync.port!);
    await phone.sync.requestPairing('pc');
    final code = pc.sync.snapshot.value.pendingCode!.code;
    await phone.sync.confirmPairing('pc', code);
    await phone.sync.syncWith('pc');

    final file = File(p.join(pc.music, 'Кибер Волна - Чёрный лёд.mp3'));
    for (var i = 0; i < 100 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(file.existsSync(), isTrue);
    expect(pc.sync.snapshot.value.nearby.keys, ['phone']);
  });

  test('paired devices are found again at their last address', () async {
    await pair();
    final peer = pc.sync.snapshot.value.paired['phone']!;
    expect(peer.host, '127.0.0.1');
    expect(peer.port, phone.sync.port);

    pc.sync.forgetNearbyForTest();
    expect(pc.sync.snapshot.value.nearby, isEmpty);
    await pc.sync.probeNow();
    expect(pc.sync.snapshot.value.nearby.keys, ['phone']);
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

  group('streaming and remote downloads', () {
    Future<List<int>> get(String url, {String? range}) async {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      if (range != null) request.headers.set('range', range);
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      client.close();
      return [response.statusCode, ...bytes];
    }

    test('stream a PC track with ranges; tampered links are refused', () async {
      await pc.addMusic(['test/fixtures/audio/neon_rain.m4a']);
      await pair();
      await phone.sync.syncWith('pc');
      final id = (await pc.db.select(pc.db.tracks).getSingle()).id;

      final url = phone.sync.streamUrl(id)!;
      final original = File('test/fixtures/audio/neon_rain.m4a')
          .readAsBytesSync();

      final part = await get(url, range: 'bytes=100-199');
      expect(part.first, HttpStatus.partialContent);
      expect(part.sublist(1), original.sublist(100, 200));

      final whole = await get(url);
      expect(whole.first, HttpStatus.ok);
      expect(whole.length - 1, original.length);

      final cover = await get(phone.sync.coverUrl(id)!);
      expect(cover.first, HttpStatus.ok);

      // Flip the first token character (always a real change).
      final forged = url.replaceFirstMapped(
        RegExp(r'tok=([0-9a-f])'),
        (m) => 'tok=${m.group(1) == '0' ? '1' : '0'}',
      );
      expect((await get(forged)).first, HttpStatus.unauthorized);
    });

    test('phone asks the PC to download; the file comes back', () async {
      final remote = _FakeRemote();
      pc.sync.remoteDownloads = remote;
      await pair();
      const wanted = DownloadCandidate(
        service: MusicService.youtube,
        sourceId: 'vid',
        sourceUrl: 'https://www.youtube.com/watch?v=vid',
        title: 'Neon Rain',
        artist: 'Synth Rider',
        durationMs: 3000,
      );

      await phone.sync.remoteDownload('pc', [wanted]);
      expect(remote.enqueued.single.sourceUrl, wanted.sourceUrl);

      // The PC "downloads" it: file in its library, source remembered.
      await pc.addMusic(['test/fixtures/audio/neon_rain.m4a']);
      await LibraryRepository(pc.db, const CoverStore('/')).markSource(
        (await pc.db.select(pc.db.tracks).getSingle()).id,
        source: 'youtube',
        sourceUrl: wanted.sourceUrl,
      );

      await phone.sync.syncWith('pc');
      expect(await phone.titles(), ['Neon Rain']);
    });

    test('preview through the PC', () async {
      final remote = _FakeRemote()
        ..previewFile = 'test/fixtures/audio/neon_rain.m4a';
      pc.sync.remoteDownloads = remote;
      await pair();
      const c = DownloadCandidate(
        service: MusicService.youtube,
        sourceId: 'vid',
        sourceUrl: 'https://www.youtube.com/watch?v=vid',
        title: 't',
        artist: 'a',
        durationMs: 1,
      );
      final stream = await phone.sync.remotePreview('pc', c);
      expect((await get(stream.url)).first, HttpStatus.ok);
    });

    test('save a streamed track to the phone', () async {
      await pc.addMusic(['test/fixtures/audio/neon_rain.m4a']);
      await pair();
      await phone.sync.syncWith('pc');
      final id = (await pc.db.select(pc.db.tracks).getSingle()).id;

      await phone.sync.saveToDevice(id);
      expect(await phone.titles(), ['Neon Rain']);
    });
  });
}

/// Records what a phone asked the PC to do.
class _FakeRemote implements RemoteDownloads {
  final enqueued = <DownloadCandidate>[];
  String previewFile = '';

  @override
  Future<void> enqueue(List<DownloadCandidate> items) async =>
      enqueued.addAll(items);

  @override
  Future<PreviewStream> preview(DownloadCandidate candidate) async =>
      PreviewStream(previewFile);
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
  List<String>? getStringList(String key) =>
      _inner.getStringList('$_prefix$key');
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _inner.setStringList('$_prefix$key', value);
  @override
  Future<bool> setBool(String key, bool value) =>
      _inner.setBool('$_prefix$key', value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
