@TestOn('vm')
library;

import 'package:device_lab/capabilities/device_capability.dart';
import 'package:device_lab/features/devices/presentation/providers/device_providers.dart';
import 'package:device_lab/features/devices/presentation/screens/device_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

import '../local_setup/native_capability_support.dart';

void main() {
  testWidgets(
    'LAN builder retries storage and prepares a real draft without starting network services',
    (tester) async {
      final fixture = (await NativeCapabilityFixture.create(tester))
        ..deny = true;
      await tester.pumpWidget(capabilityHost(buildDeviceLabCapability));
      await waitForCapability(
        tester,
        () => find.text('Retry').evaluate().isNotEmpty,
      );
      fixture.deny = false;
      await tester.tap(find.text('Retry'));
      await waitForCapability(
        tester,
        () => find.byType(DevicePage).evaluate().isNotEmpty,
      );
      final session = ProviderScope.containerOf(
        tester.element(find.byType(DevicePage)),
      ).read(deviceSessionProvider);
      expect(session.state.hostUri, isNull);
      session.edit('LAN owner persisted draft');
      expect(
        await completeCapability(tester, CapabilityLifecycle.instance.prepare),
        true,
      );
      expect(session.state.dirty, false);
      final persisted = await fixture.read(tester, 'device_lab');
      expect(persisted.toString(), contains('LAN owner persisted draft'));
      session.edit('owner remains alive after prepare');
      expect(session.state.dirty, true);
      await completeCapability(tester, CapabilityLifecycle.instance.close);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
