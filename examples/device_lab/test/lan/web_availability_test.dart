import 'package:device_lab/features/devices/data/device_discovery_web.dart';
import 'package:device_lab/features/devices/data/device_host_web.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Target implements DeviceCommandTarget {
  int commands = 0;
  @override
  Future<Map<String, Object?>> execute(DeviceCommand command) async {
    commands++;
    return {};
  }
}

void main() {
  test(
    'browser cannot discover, advertise or host and never dispatches commands',
    () async {
      final discovery = createDeviceDiscovery();
      expect(await discovery.changes.toList(), isEmpty);
      await expectLater(discovery.start(), throwsA(isA<UnsupportedError>()));
      await discovery.close();
      await discovery.close();
      await expectLater(
        advertiseDevice('browser', 9876),
        throwsA(isA<UnsupportedError>()),
      );
      final target = _Target();
      expect(canHostDevices, false);
      await expectLater(
        startDeviceHost(target),
        throwsA(isA<UnsupportedError>()),
      );
      expect(target.commands, 0);
    },
  );
}
