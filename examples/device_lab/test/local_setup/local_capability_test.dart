@TestOn('vm')
library;

import 'package:device_lab/local_capabilities.dart';
import 'package:device_lab/features/local_setup/presentation/screens/local_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

import 'native_capability_support.dart';

void main() {
  testWidgets(
    'common local capability owns persistent storage with no incoming or LAN dependency',
    (tester) async {
      final fixture = await NativeCapabilityFixture.create(tester);
      await tester.pumpWidget(
        capabilityHost((_) => const LocalCapability(onboarding: false)),
      );
      await waitForCapability(
        tester,
        () => find.byType(LocalSetupPage).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Text'),
        'local independent owner',
      );
      expect(
        await completeCapability(tester, CapabilityLifecycle.instance.prepare),
        true,
      );
      expect(
        (await fixture.read(tester, 'incoming_intents')).toString(),
        contains('local independent owner'),
      );
      await completeCapability(tester, CapabilityLifecycle.instance.close);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
