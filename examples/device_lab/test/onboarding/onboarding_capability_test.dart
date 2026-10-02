@TestOn('vm')
library;

import 'package:device_lab/onboarding_capability.dart';
import 'package:device_lab/features/local_setup/presentation/providers/local_setup_providers.dart';
import 'package:device_lab/features/local_setup/presentation/screens/local_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

import '../local_setup/native_capability_support.dart';

void main() {
  testWidgets(
    'onboarding builder retries real storage, saves at prepare and releases only at close',
    (tester) async {
      final fixture = (await NativeCapabilityFixture.create(tester))
        ..deny = true;
      await tester.pumpWidget(capabilityHost(buildOnboardingCapability));
      await waitForCapability(
        tester,
        () => find.text('Retry').evaluate().isNotEmpty,
      );
      expect(find.textContaining('fixture directory denied'), findsOneWidget);
      fixture.deny = false;
      await tester.tap(find.text('Retry'));
      await waitForCapability(
        tester,
        () => find.text('Skip for now').evaluate().isNotEmpty,
      );
      expect(fixture.requests, 2);
      await tester.tap(find.text('Skip for now'));
      await waitForCapability(
        tester,
        () => find.widgetWithText(TextField, 'Text').evaluate().isNotEmpty,
      );
      final session = ProviderScope.containerOf(
        tester.element(find.byType(LocalSetupPage)),
      ).read(localSetupSessionProvider);
      await tester.enterText(
        find.widgetWithText(TextField, 'Text'),
        'native persisted 正文',
      );
      expect(
        await completeCapability(tester, CapabilityLifecycle.instance.prepare),
        true,
      );
      expect(
        (await fixture.read(tester, 'onboarding'))['documents'],
        containsPair('welcome', containsPair('text', 'native persisted 正文')),
      );
      // A cancelled host exit may keep using the same owner after prepare.
      session.edit('still usable');
      expect(session.dirty, true);
      await completeCapability(tester, session.save);
      await completeCapability(tester, CapabilityLifecycle.instance.close);
      await tester.pumpWidget(const SizedBox());
      await expectLater(
        session.configure(session.onboarding.state),
        throwsStateError,
      );
    },
  );
}
