@TestOn('vm')
library;

import 'dart:io';

import 'package:device_lab/features/devices/application/device_protocol.dart';
import 'package:device_lab/features/devices/data/device_client.dart';
import 'package:device_lab/features/devices/data/device_host_native.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Target implements DeviceCommandTarget {
  bool paused = false;
  int commands = 0;
  @override
  Future<Map<String, Object?>> execute(DeviceCommand command) async {
    commands++;
    if (command == DeviceCommand.pauseTask) paused = true;
    if (command == DeviceCommand.resumeTask) paused = false;
    return {'paused': paused, 'documents': 1};
  }
}

void main() {
  // Installed Workbench recipes run after its widget binding is initialized.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real loopback WebSocket pairs, rejects a bad code and controls only known tasks', () async {
    final target = _Target();
    final host = await startDeviceHost(target);
    final client = PairedDeviceClient();
    try {
      await expectLater(client.connect(host.uri, 'wrong'), throwsStateError);
      await client.connect(host.uri, host.pairingCode);
      expect(client.state, DeviceConnectionState.paired);
      expect((await client.execute(DeviceCommand.summary))['documents'], 1);
      expect((await client.execute(DeviceCommand.pauseTask))['paused'], true);
      expect((await client.execute(DeviceCommand.resumeTask))['paused'], false);
      expect(target.commands, 3);
    } finally {
      await client.close();
      await host.close();
    }
    expect(client.state, DeviceConnectionState.closed);
  });
  test('reconnect pairs the new generation after transport loss and cleanup cancels retry timers', () async {
    final target = _Target();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    var host = SocketDeviceHost(
      server,
      PairedDeviceProtocol(target, pairingCode: '123456'),
    );
    final client = PairedDeviceClient();
    try {
      await client.connect(host.uri, '123456');
      final reconnecting = client.changes.firstWhere(
        (state) => state == DeviceConnectionState.reconnecting,
      );
      await host.close();
      await reconnecting;
      final reconnected = client.changes.firstWhere(
        (state) => state == DeviceConnectionState.paired,
      );
      host = SocketDeviceHost(
        await HttpServer.bind(InternetAddress.loopbackIPv4, port),
        PairedDeviceProtocol(target, pairingCode: '123456'),
      );
      await reconnected.timeout(const Duration(seconds: 8));
      expect((await client.execute(DeviceCommand.summary))['documents'], 1);
    } finally {
      await client.close();
      await host.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(client.state, DeviceConnectionState.closed);
  });
}
