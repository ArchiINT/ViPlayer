import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/sync/sync_auth.dart';

void main() {
  test('both devices derive the same secret, order-independent', () {
    final a = SyncAuth.pairingSecret('123456', 'pc', 'phone');
    final b = SyncAuth.pairingSecret('123456', 'phone', 'pc');
    expect(a, b);
    expect(SyncAuth.pairingSecret('123457', 'pc', 'phone'), isNot(a));
  });

  test('codes are 6 digits', () {
    for (var i = 0; i < 50; i++) {
      expect(SyncAuth.newPairingCode(), matches(RegExp(r'^\d{6}$')));
    }
  });

  test('signatures verify, and fail when anything changes', () {
    final secret = SyncAuth.pairingSecret('000111', 'a', 'b');
    final now = DateTime.now();
    final t = now.millisecondsSinceEpoch;
    final sig = SyncAuth.sign(secret, 'GET', '/changes?since=5', t);

    bool check({
      String s = '',
      String m = 'GET',
      String p = '/changes?since=5',
      int? time,
      DateTime? at,
    }) => SyncAuth.verify(
      secret: s.isEmpty ? secret : s,
      method: m,
      path: p,
      timeMs: time ?? t,
      signature: sig,
      now: at ?? now,
    );

    expect(check(), isTrue);
    expect(check(m: 'POST'), isFalse);
    expect(check(p: '/changes?since=0'), isFalse);
    expect(check(s: 'other'), isFalse);
    expect(check(time: t + 1), isFalse);
    // Replayed much later.
    expect(check(at: now.add(const Duration(minutes: 10))), isFalse);
  });

  test('pairing codes expire after too many attempts', () {
    final pending = PendingPairing(
      peerId: 'x',
      peerName: 'X',
      peerPlatform: 'phone',
      code: '123456',
    );
    expect(pending.expired, isFalse);
    pending.attempts = PendingPairing.maxAttempts;
    expect(pending.expired, isTrue);
  });
}
