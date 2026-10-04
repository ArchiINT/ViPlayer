import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/sync/sync_service.dart';
import 'package:viplayer/features/sync/sync_screen.dart';

void main() {
  test('device addresses: port is optional, nonsense is refused', () {
    expect(parseDeviceAddress(' 192.168.1.20 '), (
      '192.168.1.20',
      SyncService.defaultHttpPort,
    ));
    expect(parseDeviceAddress('10.0.0.5:41234'), ('10.0.0.5', 41234));
    for (final bad in [
      '',
      '192.168.1',
      '192.168.1.256',
      '192.168.1.20:',
      '192.168.1.20:70000',
      '192.168.1.20:0',
      'pc.local',
      '192,168,1,20',
    ]) {
      expect(parseDeviceAddress(bad), isNull, reason: bad);
    }
  });
}
