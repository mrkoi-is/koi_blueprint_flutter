import 'dart:convert';

import 'package:device_lab/features/devices/application/device_protocol.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Target implements DeviceCommandTarget {
  int operations = 0;
  @override
  Future<Map<String, Object?>> execute(DeviceCommand command) async => {
    'count': ++operations,
    'command': command.name,
  };
}

void main() {
  test('only paired finite commands execute; duplicate IDs are idempotent and stale generations fail', () async {
    final target = _Target();
    final protocol = PairedDeviceProtocol(target, pairingCode: '123456');
    Future<Map<String, Object?>> send(Map<String, Object?> value) =>
        protocol.receive(jsonEncode({'version': 1, 'id': 'request', ...value}));
    await expectLater(send({'command': 'pauseTask'}), throwsStateError);
    final pair = await send({'command': 'pair', 'code': '123456'});
    final request = {
      'token': pair['token'],
      'generation': pair['generation'],
      'command': 'pauseTask',
    };
    final replies = await Future.wait([send(request), send(request)]);
    expect(replies.first, replies.last);
    expect(target.operations, 1);
    await expectLater(
      send({...request, 'command': 'resumeTask'}),
      throwsFormatException,
    );
    await expectLater(
      send({...request, 'id': 'arbitrary', 'command': 'exec'}),
      throwsFormatException,
    );
    final restarted = PairedDeviceProtocol(target, pairingCode: '123456');
    await expectLater(
      restarted.receive(jsonEncode({'version': 1, 'id': 'stale', ...request})),
      throwsStateError,
    );
    expect(target.operations, 1);
  });
  test('pair attempts and message size/version are bounded', () async {
    final protocol = PairedDeviceProtocol(_Target(), pairingCode: '123456');
    for (var i = 0; i < 5; i++) {
      await expectLater(
        protocol.receive(
          jsonEncode({
            'version': 1,
            'id': 'pair$i',
            'command': 'pair',
            'code': 'wrong',
          }),
        ),
        throwsStateError,
      );
    }
    await expectLater(
      protocol.receive(
        jsonEncode({
          'version': 1,
          'id': 'correct',
          'command': 'pair',
          'code': '123456',
        }),
      ),
      throwsStateError,
    );
    await expectLater(
      protocol.receive('x' * (16 * 1024 + 1)),
      throwsFormatException,
    );
    await expectLater(protocol.receive('{"version":2}'), throwsFormatException);
  });
}
