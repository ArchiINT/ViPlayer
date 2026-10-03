import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../download/download_models.dart';
import '../download/download_service.dart';
import 'changeset.dart';
import 'discovery.dart';
import 'peer_store.dart';
import 'sync_auth.dart';

/// What a desktop offers to its phone: downloads the phone cannot do
/// itself (YouTube) and previews of them. Implemented by the download
/// module; kept as an interface so sync does not depend on it.
abstract interface class RemoteDownloads {
  Future<void> enqueue(List<DownloadCandidate> items);
  Future<PreviewStream> preview(DownloadCandidate candidate);
}

enum PeerPhase { idle, syncing, error }

/// Sync state of one paired device, for the UI.
@immutable
class PeerSyncState {
  const PeerSyncState({
    this.phase = PeerPhase.idle,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.error,
  });

  final PeerPhase phase;
  final int filesDone;
  final int filesTotal;
  final String? error;
}

@immutable
class SyncSnapshot {
  const SyncSnapshot({
    this.deviceName = '',
    this.running = false,
    this.nearby = const {},
    this.paired = const {},
    this.states = const {},
    this.remoteFiles = const {},
    this.pendingCode,
  });

  /// How this device appears to others.
  final String deviceName;
  final bool running;

  /// Devices currently visible on the network, by id.
  final Map<String, NearbyDevice> nearby;
  final Map<String, PairedPeer> paired;
  final Map<String, PeerSyncState> states;

  /// Track ids each paired peer has a file for (from its last listing):
  /// what can be streamed from it.
  final Map<String, Set<String>> remoteFiles;

  /// Code to show while another device is pairing with this one.
  final PendingPairing? pendingCode;

  SyncSnapshot copyWith({
    String? deviceName,
    bool? running,
    Map<String, NearbyDevice>? nearby,
    Map<String, PairedPeer>? paired,
    Map<String, PeerSyncState>? states,
    Map<String, Set<String>>? remoteFiles,
    PendingPairing? pendingCode,
    bool clearPending = false,
  }) => SyncSnapshot(
    deviceName: deviceName ?? this.deviceName,
    running: running ?? this.running,
    nearby: nearby ?? this.nearby,
    paired: paired ?? this.paired,
    states: states ?? this.states,
    remoteFiles: remoteFiles ?? this.remoteFiles,
    pendingCode: clearPending ? null : pendingCode ?? this.pendingCode,
  );
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Peer-to-peer sync over the local network (docs/SYNC.md).
///
/// Every device runs a small HTTP server and announces itself by UDP.
/// Paired devices exchange changesets in both directions, then the
/// initiator fetches the audio files it should have:
///  * a desktop takes every track the peer has a file for;
///  * a phone takes liked tracks and tracks of offline playlists (or all,
///    if "copy everything" is on).
class SyncService {
  SyncService({
    required this._db,
    required this._store,
    required this.deviceId,
    required this.kind,
    required String deviceName,
    required this.downloadDirectory,
    required this.coversDirectory,
    required Future<String> Function(String path) importFile,
    this.discoveryPort = Discovery.defaultPort,
    this.httpPort = defaultHttpPort,
    this.enableDiscovery = true,
  }) : _import = importFile,
       _name = deviceName {
    _snapshot.value = SyncSnapshot(
      deviceName: deviceName,
      paired: _store.load(),
    );
  }

  final AppDatabase _db;
  final PeerStore _store;
  final String deviceId;
  final DeviceKind kind;
  final String downloadDirectory;

  /// Where the library keeps cover images (served to streaming peers).
  final String coversDirectory;
  final Future<String> Function(String path) _import;
  final int discoveryPort;
  final int httpPort;
  final bool enableDiscovery;

  static const defaultHttpPort = 48126;

  /// Desktop only: lets paired phones download and preview through us.
  RemoteDownloads? remoteDownloads;

  /// How long stream links stay valid (a long album with pauses).
  static const streamTokenLifetime = Duration(hours: 12);

  /// Previews prepared for phones: id -> local file.
  final _previews = <String, String>{};
  String _name;

  /// Minimum time between two automatic syncs with the same peer.
  static const autoSyncCooldown = Duration(minutes: 1);

  /// Wait after a local change before syncing it (batches bursts of edits).
  static const changeDebounce = Duration(seconds: 10);

  HttpServer? _server;
  Discovery? _discovery;
  StreamSubscription<NearbyDevice>? _seenSub;
  StreamSubscription<Object?>? _changesSub;
  Timer? _changeTimer;
  Timer? _expiryTimer;
  final _lastAutoSync = <String, DateTime>{};

  /// Sync in progress per peer; later requests queue behind it.
  final _running = <String, Future<void>>{};

  final _snapshot = ValueNotifier(const SyncSnapshot());
  ValueListenable<SyncSnapshot> get snapshot => _snapshot;
  SyncSnapshot get _state => _snapshot.value;

  int? get port => _server?.port;
  String get deviceName => _name;

  // ------------------------------------------------------------ lifecycle

  Future<void> start() async {
    if (_server != null) return;
    // A fixed port lets users allow it in their firewall (docs/SYNC.md);
    // any free port if it is taken (e.g. two instances, tests).
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!
      ..autoCompress = true
      ..listen(_handle);

    if (enableDiscovery) {
      try {
        final discovery = Discovery(
          deviceId: deviceId,
          name: _name,
          kind: kind,
          port: discoveryPort,
        );
        await discovery.start(_server!.port);
        _discovery = discovery;
        _seenSub = discovery.seen.listen(_onSeen);
      } on SocketException catch (e) {
        // Port taken / no network: manual connection still works.
        debugPrint('Sync discovery unavailable: $e');
      }
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _expire());

    // Local changes: sync them to visible peers shortly after.
    var first = true;
    _changesSub = _db.select(_db.syncState).watch().listen((_) {
      if (first) {
        first = false;
        return;
      }
      _changeTimer?.cancel();
      _changeTimer = Timer(changeDebounce, _syncVisiblePeers);
    });
    _set(_state.copyWith(running: true));
  }

  Future<void> stop() async {
    _changeTimer?.cancel();
    _expiryTimer?.cancel();
    await _changesSub?.cancel();
    await _seenSub?.cancel();
    await _discovery?.stop();
    await _server?.close(force: true);
    _server = null;
    _set(_state.copyWith(running: false, nearby: {}));
  }

  Future<void> rename(String name) async {
    _name = name;
    _discovery?.name = name;
    await _store.setDeviceName(name);
    _set(_state.copyWith(deviceName: name));
    _discovery?.announce();
  }

  // ------------------------------------------------------------ discovery

  void _onSeen(NearbyDevice device) {
    final isNew = !_state.nearby.containsKey(device.id);
    _set(_state.copyWith(nearby: {..._state.nearby, device.id: device}));
    if (isNew) _discovery?.announce(); // answer quickly

    final last = _lastAutoSync[device.id];
    if (_state.paired.containsKey(device.id) &&
        (last == null || DateTime.now().difference(last) > autoSyncCooldown)) {
      _lastAutoSync[device.id] = DateTime.now();
      unawaited(syncWith(device.id).catchError((_) {}));
    }
  }

  void _expire() {
    final now = DateTime.now();
    final alive = {
      for (final d in _state.nearby.values)
        if (now.difference(d.lastSeen) < Discovery.expiry) d.id: d,
    };
    if (alive.length != _state.nearby.length) {
      _set(_state.copyWith(nearby: alive));
    }
  }

  /// Adds a device by address (when broadcast discovery is blocked).
  Future<NearbyDevice> connect(String host, int port) async {
    final info = await _json('GET', host, port, '/hello', signed: false);
    final device = NearbyDevice(
      id: info['id']! as String,
      name: info['name']! as String,
      kind: DeviceKind.fromName(info['kind'] as String?),
      host: host,
      port: port,
      // Manually added devices do not expire with discovery.
      lastSeen: DateTime.now().add(const Duration(days: 3650)),
    );
    _set(_state.copyWith(nearby: {..._state.nearby, device.id: device}));
    return device;
  }

  void _syncVisiblePeers() {
    for (final id in _state.nearby.keys) {
      if (_state.paired.containsKey(id)) {
        unawaited(syncWith(id).catchError((_) {}));
      }
    }
  }

  // -------------------------------------------------------------- pairing

  /// Asks [deviceId] to show a pairing code.
  Future<void> requestPairing(String peerId) async {
    final device = _nearby(peerId);
    await _json(
      'POST',
      device.host,
      device.port,
      '/pair/request',
      signed: false,
      body: {'id': deviceId, 'name': _name, 'kind': kind.name},
    );
  }

  /// Completes pairing with the code shown on the other device.
  Future<PairedPeer> confirmPairing(String peerId, String code) async {
    final device = _nearby(peerId);
    final secret = SyncAuth.pairingSecret(code.trim(), deviceId, peerId);
    final response = await _json(
      'POST',
      device.host,
      device.port,
      '/pair/confirm',
      signed: false,
      body: {
        'id': deviceId,
        'name': _name,
        'kind': kind.name,
        'proof': SyncAuth.proof(secret, 'requester'),
      },
    );
    if (response['proof'] != SyncAuth.proof(secret, 'responder')) {
      throw const SyncException('wrong code');
    }
    final peer = PairedPeer(
      id: peerId,
      name: device.name,
      kind: device.kind,
      secret: secret,
    );
    await _savePeer(peer);
    unawaited(syncWith(peerId).catchError((_) {}));
    return peer;
  }

  Future<void> cancelPairingCode() async =>
      _set(_state.copyWith(clearPending: true));

  Future<void> unpair(String peerId) async {
    final peers = {..._state.paired}..remove(peerId);
    await _store.save(peers);
    _set(_state.copyWith(paired: peers));
  }

  // ----------------------------------------------------------------- sync

  /// Full exchange with a paired peer: metadata both ways, then files.
  ///
  /// If a sync with this peer is already running, waits for it and then
  /// runs again — the caller's changes may have been made after it started.
  Future<void> syncWith(String peerId) async {
    final previous = _running[peerId];
    final next = (previous ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => _syncOnce(peerId));
    _running[peerId] = next;
    try {
      await next;
    } finally {
      _running.removeWhere((id, f) => id == peerId && identical(f, next));
    }
  }

  Future<void> _syncOnce(String peerId) async {
    _setPeerState(peerId, const PeerSyncState(phase: PeerPhase.syncing));
    try {
      var peer = _state.paired[peerId]!;
      final device = _nearby(peerId);

      // 1. Pull their changes.
      final (theirChanges, theirCursorOfUs) = await _pull(device, peer);
      await ChangesetApplier(_db).apply(theirChanges);
      peer = peer.copyWith(cursor: theirChanges.untilRev);
      await _savePeer(peer);

      // 2. Push ours since what they already have.
      final ours = await Changeset.since(_db, theirCursorOfUs);
      if (!ours.isEmpty) {
        await _json(
          'POST',
          device.host,
          device.port,
          '/changes',
          peer: peer,
          body: ours.toJson(),
        );
      }

      // 3. Files this device should have.
      await _fetchFiles(device, peer);

      await _savePeer(peer.copyWith(lastSync: DateTime.now()));
      _setPeerState(peerId, const PeerSyncState());
    } catch (e) {
      _setPeerState(peerId, PeerSyncState(phase: PeerPhase.error, error: '$e'));
      rethrow;
    }
  }

  Future<(Changeset, int)> _pull(NearbyDevice device, PairedPeer peer) async {
    final client = HttpClient();
    try {
      final path = '/changes?since=${peer.cursor}';
      final request = await client.get(device.host, device.port, path);
      _signRequest(request, 'GET', path, peer);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw SyncException('HTTP ${response.statusCode}: $body');
      }
      final cursor = int.parse(response.headers.value('x-vp-cursor') ?? '0');
      return (
        Changeset.fromJson(jsonDecode(body) as Map<String, Object?>),
        cursor,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _fetchFiles(NearbyDevice device, PairedPeer peer) async {
    final listing = await _jsonList(device, peer, '/files');
    final available = {
      for (final f in listing) f['id']! as String: f['ext']! as String,
    };
    _set(
      _state.copyWith(
        remoteFiles: {..._state.remoteFiles, peer.id: available.keys.toSet()},
      ),
    );
    final wanted = await _wantedTrackIds();
    final todo = [
      for (final id in wanted)
        if (available.containsKey(id)) id,
    ];
    if (todo.isEmpty) return;

    var done = 0;
    _setPeerState(
      peer.id,
      PeerSyncState(phase: PeerPhase.syncing, filesTotal: todo.length),
    );
    for (final id in todo) {
      final track = await (_db.select(
        _db.tracks,
      )..where((t) => t.id.equals(id))).getSingle();
      final target = await _targetFor(track, available[id]!);
      await _download(device, peer, '/file/$id', target);
      await _import(target.path);
      done++;
      _setPeerState(
        peer.id,
        PeerSyncState(
          phase: PeerPhase.syncing,
          filesDone: done,
          filesTotal: todo.length,
        ),
      );
    }
  }

  /// Tracks this device should hold a file for but does not.
  Future<List<String>> _wantedTrackIds() async {
    final everything = kind == DeviceKind.desktop || _store.copyAllToPhone;
    final requested = _store.requestedDownloads.toList();
    final conditions = [
      if (everything) '1',
      if (!everything) ...[
        't.liked = 1',
        't.id IN (SELECT e.track_id FROM playlist_entries e '
            'JOIN playlists pl ON pl.id = e.playlist_id '
            'WHERE e.deleted = 0 AND pl.deleted = 0 AND pl.is_offline = 1)',
      ],
      if (requested.isNotEmpty)
        't.source_url IN (${List.filled(requested.length, '?').join(', ')})',
    ];
    final rows = await _db
        .customSelect(
          'SELECT t.id FROM tracks t WHERE t.deleted = 0 '
          'AND NOT EXISTS (SELECT 1 FROM track_files f WHERE f.track_id = t.id) '
          'AND (${conditions.join(' OR ')})',
          variables: [for (final u in requested) Variable.withString(u)],
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  // --------------------------------------------------------------- server

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      switch ((request.method, path)) {
        case ('GET', '/hello'):
          _sendJson(response, {
            'id': deviceId,
            'name': _name,
            'kind': kind.name,
          });
        case ('POST', '/pair/request'):
          await _onPairRequest(request);
        case ('POST', '/pair/confirm'):
          await _onPairConfirm(request);
        case ('GET', _)
            when path.startsWith('/stream/') ||
                path.startsWith('/cover/') ||
                path.startsWith('/preview/'):
          final peer = _authenticateToken(request);
          if (peer == null) {
            response.statusCode = HttpStatus.unauthorized;
            break;
          }
          await _handleStreaming(request);
        default:
          final peer = _authenticate(request);
          if (peer == null) {
            response.statusCode = HttpStatus.unauthorized;
            break;
          }
          await _handleSigned(request, peer);
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('$e');
    } finally {
      await response.close();
    }
  }

  Future<void> _handleSigned(HttpRequest request, PairedPeer peer) async {
    final response = request.response;
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/changes') {
      final since = int.tryParse(request.uri.queryParameters['since'] ?? '');
      final changes = await Changeset.since(_db, since ?? 0);
      response.headers.set('x-vp-cursor', '${peer.cursor}');
      _sendJson(response, changes.toJson());
    } else if (request.method == 'POST' && path == '/changes') {
      final body = await utf8.decoder.bind(request).join();
      final changes = Changeset.fromJson(
        jsonDecode(body) as Map<String, Object?>,
      );
      await ChangesetApplier(_db).apply(changes);
      await _savePeer(peer.copyWith(cursor: changes.untilRev));
      _sendJson(response, {'ok': true});
    } else if (request.method == 'GET' && path == '/files') {
      final rows = await _db
          .customSelect(
            'SELECT f.track_id AS id, MIN(f.path) AS path FROM track_files f '
            'JOIN tracks t ON t.id = f.track_id WHERE t.deleted = 0 '
            'GROUP BY f.track_id',
            readsFrom: {_db.trackFiles, _db.tracks},
          )
          .get();
      _sendJson(response, [
        for (final r in rows)
          {
            'id': r.read<String>('id'),
            'ext': p.extension(r.read<String>('path')),
          },
      ]);
    } else if (request.method == 'GET' && path.startsWith('/file/')) {
      final id = await _canonical(path.substring('/file/'.length));
      final row = await (_db.select(
        _db.trackFiles,
      )..where((f) => f.trackId.equals(id))).get();
      final file = row.isEmpty ? null : File(row.first.path);
      if (file == null || !file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers
        ..contentType = ContentType.binary
        ..contentLength = await file.length();
      await response.addStream(file.openRead());
    } else if (request.method == 'POST' && path == '/remote/download') {
      final remote = remoteDownloads;
      if (remote == null) {
        response.statusCode = HttpStatus.notImplemented;
        return;
      }
      final body = await _readJson(request);
      await remote.enqueue([
        for (final item in body['items']! as List<Object?>)
          DownloadCandidate.fromJson(item! as Map<String, Object?>),
      ]);
      _sendJson(response, {'ok': true});
    } else if (request.method == 'POST' && path == '/remote/preview') {
      final remote = remoteDownloads;
      if (remote == null) {
        response.statusCode = HttpStatus.notImplemented;
        return;
      }
      final body = await _readJson(request);
      final stream = await remote.preview(DownloadCandidate.fromJson(body));
      if (stream.url.startsWith('http')) {
        _sendJson(response, {'url': stream.url, 'headers': stream.headers});
      } else {
        // A local file: hand out a streaming path for it.
        final id = '${DateTime.now().microsecondsSinceEpoch}';
        _previews[id] = stream.url;
        _sendJson(response, {'path': '/preview/$id'});
      }
    } else {
      response.statusCode = HttpStatus.notFound;
    }
  }

  /// Audio, covers and previews for streaming (token-authenticated: media
  /// players cannot sign each range request).
  Future<void> _handleStreaming(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    File? file;
    var type = ContentType.binary;
    if (path.startsWith('/preview/')) {
      final local = _previews[path.substring('/preview/'.length)];
      file = local == null ? null : File(local);
    } else {
      final id = await _canonical(path.substring(path.indexOf('/', 1) + 1));
      final rows = await (_db.select(
        _db.trackFiles,
      )..where((f) => f.trackId.equals(id))).get();
      if (path.startsWith('/stream/')) {
        file = rows.isEmpty ? null : File(rows.first.path);
      } else {
        final coverId = rows.map((r) => r.coverId).nonNulls.firstOrNull;
        file = coverId == null ? null : File(p.join(coversDirectory, coverId));
        type = ContentType('image', 'jpeg');
      }
    }
    if (file == null || !file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    await serveFile(request, file, type);
  }

  /// Sends [file], honouring a `Range` header (players seek with ranges).
  static Future<void> serveFile(
    HttpRequest request,
    File file,
    ContentType type,
  ) async {
    final response = request.response;
    final length = await file.length();
    response.headers
      ..contentType = type
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = RegExp(r'^bytes=(\d*)-(\d*)$')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range == null) {
      response.contentLength = length;
      await response.addStream(file.openRead());
      return;
    }
    var start = int.tryParse(range.group(1)!) ?? 0;
    var end = int.tryParse(range.group(2)!) ?? length - 1;
    if (range.group(1)!.isEmpty && range.group(2)!.isNotEmpty) {
      // "bytes=-500": the last 500 bytes.
      start = length - end;
      end = length - 1;
    }
    if (start >= length || start > end) {
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      return;
    }
    end = end.clamp(start, length - 1);
    response
      ..statusCode = HttpStatus.partialContent
      ..contentLength = end - start + 1
      ..headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    await response.addStream(file.openRead(start, end + 1));
  }

  Future<String> _canonical(String trackId) async {
    final alias = await (_db.select(
      _db.trackAliases,
    )..where((a) => a.aliasId.equals(trackId))).getSingleOrNull();
    return alias?.trackId ?? trackId;
  }

  Future<void> _onPairRequest(HttpRequest request) async {
    final body = await _readJson(request);
    final pending = PendingPairing(
      peerId: body['id']! as String,
      peerName: body['name']! as String,
      peerPlatform: body['kind'] as String? ?? 'desktop',
      code: SyncAuth.newPairingCode(),
    );
    _set(_state.copyWith(pendingCode: pending));
    request.response.statusCode = HttpStatus.accepted;
  }

  Future<void> _onPairConfirm(HttpRequest request) async {
    final body = await _readJson(request);
    final pending = _state.pendingCode;
    final peerId = body['id'] as String?;
    if (pending == null || pending.peerId != peerId || pending.expired) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    pending.attempts++;
    final secret = SyncAuth.pairingSecret(pending.code, deviceId, peerId!);
    if (!SyncAuth.constantTimeEquals(
      body['proof'] as String? ?? '',
      SyncAuth.proof(secret, 'requester'),
    )) {
      request.response.statusCode = HttpStatus.forbidden;
      if (pending.expired) _set(_state.copyWith(clearPending: true));
      return;
    }
    await _savePeer(
      PairedPeer(
        id: peerId,
        name: body['name']! as String,
        kind: DeviceKind.fromName(body['kind'] as String?),
        secret: secret,
      ),
    );
    _set(_state.copyWith(clearPending: true));
    _sendJson(request.response, {
      'id': deviceId,
      'name': _name,
      'kind': kind.name,
      'proof': SyncAuth.proof(secret, 'responder'),
    });
  }

  /// Long-lived link signature for media players (see [streamUrl]).
  PairedPeer? _authenticateToken(HttpRequest request) {
    final q = request.uri.queryParameters;
    final peer = _state.paired[q['from']];
    final expires = int.tryParse(q['exp'] ?? '');
    final token = q['tok'];
    if (peer == null || expires == null || token == null) return null;
    if (DateTime.now().millisecondsSinceEpoch > expires) return null;
    final expected = SyncAuth.sign(
      peer.secret,
      'TOKEN',
      request.uri.path,
      expires,
    );
    return SyncAuth.constantTimeEquals(expected, token) ? peer : null;
  }

  PairedPeer? _authenticate(HttpRequest request) {
    final peer = _state.paired[request.headers.value('x-vp-from')];
    final time = int.tryParse(request.headers.value('x-vp-time') ?? '');
    final signature = request.headers.value('x-vp-sig');
    if (peer == null || time == null || signature == null) return null;
    return SyncAuth.verify(
          secret: peer.secret,
          method: request.method,
          path: request.uri.toString(),
          timeMs: time,
          signature: signature,
        )
        ? peer
        : null;
  }

  // --------------------------------------------------------------- client

  void _signRequest(
    HttpClientRequest request,
    String method,
    String path,
    PairedPeer peer,
  ) {
    final time = DateTime.now().millisecondsSinceEpoch;
    request.headers
      ..set('x-vp-from', deviceId)
      ..set('x-vp-time', '$time')
      ..set('x-vp-sig', SyncAuth.sign(peer.secret, method, path, time));
  }

  Future<Map<String, Object?>> _json(
    String method,
    String host,
    int port,
    String path, {
    PairedPeer? peer,
    bool signed = true,
    Object? body,
  }) async =>
      jsonDecode(await _call(method, host, port, path, peer, signed, body))
          as Map<String, Object?>;

  Future<List<Map<String, Object?>>> _jsonList(
    NearbyDevice device,
    PairedPeer peer,
    String path,
  ) async => (jsonDecode(
    await _call('GET', device.host, device.port, path, peer, true),
  ) as List<Object?>).cast<Map<String, Object?>>();

  Future<String> _call(
    String method,
    String host,
    int port,
    String path,
    PairedPeer? peer,
    bool signed, [
    Object? body,
  ]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.open(method, host, port, path);
      if (signed) _signRequest(request, method, path, peer!);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode >= 400) {
        throw SyncException(
          response.statusCode == HttpStatus.forbidden
              ? 'wrong code'
              : 'HTTP ${response.statusCode} $text',
        );
      }
      return text.isEmpty ? '{}' : text;
    } on SocketException catch (e) {
      throw SyncException('device unreachable: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _download(
    NearbyDevice device,
    PairedPeer peer,
    String path,
    File target,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final part = File('${target.path}.part');
    try {
      final request = await client.get(device.host, device.port, path);
      _signRequest(request, 'GET', path, peer);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw SyncException('file $path: HTTP ${response.statusCode}');
      }
      await response.pipe(part.openWrite());
      await part.rename(target.path);
    } finally {
      client.close(force: true);
      if (part.existsSync()) await part.delete();
    }
  }

  // ----------------------------------------------- streaming & remote use

  /// A paired desktop that is on the network now (does downloads for us).
  String? get downloadPeer {
    for (final peer in _state.paired.values) {
      if (peer.kind == DeviceKind.desktop &&
          _state.nearby.containsKey(peer.id)) {
        return peer.id;
      }
    }
    return null;
  }

  /// Online peer that has a file for [trackId], if any.
  String? _peerWithFile(String trackId) {
    for (final MapEntry(key: id, value: files) in _state.remoteFiles.entries) {
      if (files.contains(trackId) &&
          _state.nearby.containsKey(id) &&
          _state.paired.containsKey(id)) {
        return id;
      }
    }
    return null;
  }

  /// URL to stream [trackId] from a device that has it, or null.
  String? streamUrl(String trackId) =>
      _tokenUrl(_peerWithFile(trackId), '/stream/$trackId');

  String? coverUrl(String trackId) =>
      _tokenUrl(_peerWithFile(trackId), '/cover/$trackId');

  String? _tokenUrl(String? peerId, String path) {
    if (peerId == null) return null;
    final peer = _state.paired[peerId]!;
    final device = _state.nearby[peerId]!;
    final expires = DateTime.now()
        .add(streamTokenLifetime)
        .millisecondsSinceEpoch;
    final token = SyncAuth.sign(peer.secret, 'TOKEN', path, expires);
    return Uri(
      scheme: 'http',
      host: device.host,
      port: device.port,
      path: path,
      queryParameters: {'from': deviceId, 'exp': '$expires', 'tok': token},
    ).toString();
  }

  /// Copies a streamed track to this device.
  Future<void> saveToDevice(String trackId) async {
    final peerId = _peerWithFile(trackId);
    if (peerId == null) {
      throw const SyncException('device is not on the network');
    }
    final track = await (_db.select(
      _db.tracks,
    )..where((t) => t.id.equals(trackId))).getSingle();
    final ext = await _remoteExtension(peerId, trackId);
    final target = await _targetFor(track, ext);
    await _download(
      _nearby(peerId),
      _state.paired[peerId]!,
      '/file/$trackId',
      target,
    );
    await _import(target.path);
  }

  Future<String> _remoteExtension(String peerId, String trackId) async {
    final listing = await _jsonList(
      _nearby(peerId),
      _state.paired[peerId]!,
      '/files',
    );
    return listing.firstWhere(
          (f) => f['id'] == trackId,
          orElse: () => const {'ext': '.m4a'},
        )['ext']!
        as String;
  }

  /// Asks a paired desktop to download [items]; their files come to this
  /// device on the next sync.
  Future<void> remoteDownload(
    String peerId,
    List<DownloadCandidate> items,
  ) async {
    final device = _nearby(peerId);
    await _store.addRequestedDownloads(items.map((c) => c.sourceUrl));
    await _json(
      'POST',
      device.host,
      device.port,
      '/remote/download',
      peer: _state.paired[peerId],
      body: {
        'items': [for (final c in items) c.toJson()],
      },
    );
  }

  /// Preview prepared by a paired desktop (e.g. YouTube on a phone).
  Future<PreviewStream> remotePreview(
    String peerId,
    DownloadCandidate candidate,
  ) async {
    final device = _nearby(peerId);
    final response = await _json(
      'POST',
      device.host,
      device.port,
      '/remote/preview',
      peer: _state.paired[peerId],
      body: candidate.toJson(),
    );
    if (response['url'] case final String url) {
      return PreviewStream(
        url,
        headers: (response['headers'] as Map<String, Object?>? ?? const {}).map(
          (k, v) => MapEntry(k, '$v'),
        ),
      );
    }
    return PreviewStream(_tokenUrl(peerId, response['path']! as String)!);
  }

  Future<File> _targetFor(TrackRow track, String ext) async {
    await Directory(downloadDirectory).create(recursive: true);
    final base = DownloadService.safeFileName(
      track.artist.isEmpty ? track.title : '${track.artist} - ${track.title}',
    );
    var target = File(p.join(downloadDirectory, '$base$ext'));
    for (var n = 2; target.existsSync(); n++) {
      target = File(p.join(downloadDirectory, '$base ($n)$ext'));
    }
    return target;
  }

  // -------------------------------------------------------------- helpers

  NearbyDevice _nearby(String id) =>
      _state.nearby[id] ??
      (throw const SyncException('device is not on the network'));

  Future<void> _savePeer(PairedPeer peer) async {
    final peers = {..._state.paired, peer.id: peer};
    await _store.save(peers);
    _set(_state.copyWith(paired: peers));
  }

  void _setPeerState(String id, PeerSyncState state) =>
      _set(_state.copyWith(states: {..._state.states, id: state}));

  void _set(SyncSnapshot next) => _snapshot.value = next;

  static void _sendJson(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }

  static Future<Map<String, Object?>> _readJson(HttpRequest request) async =>
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;

  Future<void> dispose() async {
    await stop();
    _snapshot.dispose();
  }
}
