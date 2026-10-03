import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/sync/discovery.dart';
import 'package:viplayer/core/sync/peer_store.dart';

void main() {
  test('two devices on one machine hear each other', () async {
    // Unicast over loopback on two ports: tests the protocol without
    // depending on the machine's firewall letting broadcasts in.
    final pc = Discovery(
      deviceId: 'pc',
      name: 'Мой ПК',
      kind: DeviceKind.desktop,
      port: 48998,
      targetPort: 48999,
      targetAddress: InternetAddress.loopbackIPv4,
    );
    final phone = Discovery(
      deviceId: 'phone',
      name: 'Phone',
      kind: DeviceKind.phone,
      port: 48999,
      targetPort: 48998,
      targetAddress: InternetAddress.loopbackIPv4,
    );
    final heardByPc = pc.seen.first;
    final heardByPhone = phone.seen.first;
    await pc.start(1111);
    await phone.start(2222);

    final a = await heardByPc.timeout(const Duration(seconds: 10));
    final b = await heardByPhone.timeout(const Duration(seconds: 10));
    expect((a.id, a.port, a.kind), ('phone', 2222, DeviceKind.phone));
    expect((b.id, b.name, b.port), ('pc', 'Мой ПК', 1111));

    await pc.stop();
    await phone.stop();
  });
}
