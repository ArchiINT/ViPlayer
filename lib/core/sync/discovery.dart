import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'peer_store.dart';

/// A ViPlayer instance seen on the local network.
@immutable
class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.host,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final String host;
  final int port;
  final DateTime lastSeen;
}

/// Finds other ViPlayer devices with a UDP broadcast "beacon":
/// `VP1|<id>|<http port>|<kind>|<name>` every few seconds.
class Discovery {
  Discovery({
    required this.deviceId,
    required this.name,
    required this.kind,
    this.port = defaultPort,
    int? targetPort,
    InternetAddress? targetAddress,
  }) : _targetPort = targetPort ?? port,
       _target = targetAddress ?? InternetAddress('255.255.255.255');

  /// Not Finanz's port: both apps may run on the same machine.
  static const defaultPort = 48125;
  static const _magic = 'VP1';
  static const _interval = Duration(seconds: 3);

  /// Devices not heard from for this long are considered gone.
  static const expiry = Duration(seconds: 15);

  final String deviceId;
  String name;
  final DeviceKind kind;
  final int port;

  // Where beacons go: the LAN broadcast address normally; tests use a
  // unicast address and a second port.
  final int _targetPort;
  final InternetAddress _target;

  RawDatagramSocket? _socket;
  Timer? _beacon;
  int? _httpPort;
  final _seen = StreamController<NearbyDevice>.broadcast();

  /// Every beacon heard from another device.
  Stream<NearbyDevice> get seen => _seen.stream;

  Future<void> start(int httpPort) async {
    _httpPort = httpPort;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket!
      ..broadcastEnabled = true
      ..listen(_onEvent);
    _beacon = Timer.periodic(_interval, (_) => announce());
    announce();
  }

  void announce() {
    final socket = _socket;
    if (socket == null || _httpPort == null) return;
    final message = utf8.encode(
      '$_magic|$deviceId|$_httpPort|${kind.name}|${Uri.encodeComponent(name)}',
    );
    try {
      socket.send(message, _target, _targetPort);
    } on SocketException {
      // No network / broadcast blocked: others may still hear nothing from
      // us, but we keep listening.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    final parts = utf8.decode(datagram.data, allowMalformed: true).split('|');
    if (parts.length != 5 || parts[0] != _magic || parts[1] == deviceId) {
      return;
    }
    final httpPort = int.tryParse(parts[2]);
    if (httpPort == null) return;
    _seen.add(
      NearbyDevice(
        id: parts[1],
        name: Uri.decodeComponent(parts[4]),
        kind: DeviceKind.fromName(parts[3]),
        host: datagram.address.address,
        port: httpPort,
        lastSeen: DateTime.now(),
      ),
    );
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _socket?.close();
    _socket = null;
    await _seen.close();
  }
}
