import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What kind of device a peer is — decides which files it receives
/// (docs/SYNC.md: the PC gets everything, the phone gets offline music).
enum DeviceKind {
  desktop,
  phone;

  static DeviceKind fromName(String? name) =>
      name == 'phone' ? DeviceKind.phone : DeviceKind.desktop;
}

/// A device this one is paired with.
@immutable
class PairedPeer {
  const PairedPeer({
    required this.id,
    required this.name,
    required this.kind,
    required this.secret,
    this.cursor = 0,
    this.lastSync,
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final String secret;

  /// The peer's revision we have received up to (next request: since this).
  final int cursor;
  final DateTime? lastSync;

  PairedPeer copyWith({String? name, int? cursor, DateTime? lastSync}) =>
      PairedPeer(
        id: id,
        name: name ?? this.name,
        kind: kind,
        secret: secret,
        cursor: cursor ?? this.cursor,
        lastSync: lastSync ?? this.lastSync,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'secret': secret,
    'cursor': cursor,
    'lastSync': lastSync?.millisecondsSinceEpoch,
  };

  factory PairedPeer.fromJson(Map<String, Object?> j) => PairedPeer(
    id: j['id']! as String,
    name: j['name']! as String,
    kind: DeviceKind.fromName(j['kind'] as String?),
    secret: j['secret']! as String,
    cursor: (j['cursor'] as num?)?.toInt() ?? 0,
    lastSync: switch (j['lastSync']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
  );
}

/// Paired devices and this device's sync name, kept in local settings
/// (pairings are per device and never synced).
class PeerStore {
  PeerStore(this._prefs);

  final SharedPreferences _prefs;
  static const _peersKey = 'sync.peers';
  static const _nameKey = 'sync.deviceName';
  static const _copyAllKey = 'sync.copyAllToPhone';
  static const _requestedKey = 'sync.requestedDownloads';

  Map<String, PairedPeer> load() {
    final raw = _prefs.getString(_peersKey);
    if (raw == null) return {};
    final list = (jsonDecode(raw) as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(PairedPeer.fromJson);
    return {for (final p in list) p.id: p};
  }

  Future<void> save(Map<String, PairedPeer> peers) => _prefs.setString(
    _peersKey,
    jsonEncode([for (final p in peers.values) p.toJson()]),
  );

  String? get deviceName => _prefs.getString(_nameKey);
  Future<void> setDeviceName(String name) => _prefs.setString(_nameKey, name);

  /// Phone only: copy every new PC track, not just offline ones.
  bool get copyAllToPhone => _prefs.getBool(_copyAllKey) ?? false;
  Future<void> setCopyAllToPhone(bool value) =>
      _prefs.setBool(_copyAllKey, value);

  /// Source links this device asked a PC to download: their files are
  /// fetched on the next sync, whatever the copy rules say.
  Set<String> get requestedDownloads =>
      (_prefs.getStringList(_requestedKey) ?? const []).toSet();

  Future<void> addRequestedDownloads(Iterable<String> urls) => _prefs
      .setStringList(_requestedKey, {...requestedDownloads, ...urls}.toList());
}
