import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Pairing and request signing for LAN sync.
///
/// Pairing: one device shows a 6-digit code, the user types it on the
/// other. Both derive the same secret from the code and the two device ids;
/// the code itself is never sent. Afterwards every request carries an
/// HMAC of method, path and time, so other devices on the network can
/// neither read the library nor push changes.
///
/// Threat model: a home network. Traffic is not encrypted, and a recorded
/// pairing exchange could be brute-forced offline (6 digits) — pair on a
/// network you trust. See docs/SYNC.md.
abstract final class SyncAuth {
  /// Requests older/newer than this are rejected (limits replays).
  static const maxClockSkew = Duration(minutes: 5);

  static final _random = Random.secure();

  static String newPairingCode() =>
      List.generate(6, (_) => _random.nextInt(10)).join();

  static String pairingSecret(String code, String idA, String idB) {
    final ids = [idA, idB]..sort();
    return sha256
        .convert(utf8.encode('viplayer-pair|$code|${ids[0]}|${ids[1]}'))
        .toString();
  }

  /// Proof that a device knows the code, bound to its role in the exchange.
  static String proof(String secret, String role) =>
      _hmac(secret, 'pair|$role');

  static String sign(String secret, String method, String path, int timeMs) =>
      _hmac(secret, '$method $path $timeMs');

  static bool verify({
    required String secret,
    required String method,
    required String path,
    required int timeMs,
    required String signature,
    DateTime? now,
  }) {
    final skew = (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(timeMs))
        .abs();
    if (skew > maxClockSkew) return false;
    return constantTimeEquals(sign(secret, method, path, timeMs), signature);
  }

  static String _hmac(String secret, String message) => Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(message)).toString();

  /// String comparison whose duration does not depend on where the inputs
  /// differ (no timing hints for guessing signatures).
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// A pairing code waiting to be typed on the other device.
class PendingPairing {
  PendingPairing({
    required this.peerId,
    required this.peerName,
    required this.peerPlatform,
    required this.code,
    DateTime? now,
  }) : expires = (now ?? DateTime.now()).add(lifetime);

  static const lifetime = Duration(minutes: 2);
  static const maxAttempts = 5;

  final String peerId;
  final String peerName;
  final String peerPlatform;
  final String code;
  final DateTime expires;
  int attempts = 0;

  bool get expired =>
      DateTime.now().isAfter(expires) || attempts >= maxAttempts;
}
