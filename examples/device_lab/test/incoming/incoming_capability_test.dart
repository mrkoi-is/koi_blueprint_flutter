@TestOn('vm')
library;

import 'package:device_lab/incoming_capability.dart';
import 'package:device_lab/features/devices/data/incoming_links.dart';
import 'package:device_lab/features/local_setup/presentation/providers/local_setup_providers.dart';
import 'package:device_lab/features/local_setup/presentation/screens/local_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

import '../local_setup/native_capability_support.dart';

void main() {
  testWidgets(
    'incoming initializer queues cold link, borrows inbox and restores after disposal',
    (tester) async {
      final fixture = await NativeCapabilityFixture.create(tester);
      const messages = MethodChannel('com.llfbandit.app_links/messages');
      const events = MethodChannel('com.llfbandit.app_links/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        messages,
        (call) async => call.method == 'getInitialLink' ? 'koi://tasks' : null,
      );
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() async {
        await completeCapability(tester, disposeIncomingIntents);
        messenger.setMockMethodCallHandler(messages, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await completeCapability(tester, initializeIncomingIntents);
      final initialInbox = IncomingLinkInbox.instance;
      await tester.pumpWidget(capabilityHost(buildIncomingIntentsCapability));
      await waitForCapability(
        tester,
        () => find.byType(LocalSetupPage).evaluate().isNotEmpty,
      );
      final session = ProviderScope.containerOf(
        tester.element(find.byType(LocalSetupPage)),
      ).read(localSetupSessionProvider);
      await waitForCapability(tester, () => session.tab == 'tasks');
      await tester.enterText(
        find.widgetWithText(TextField, 'Text'),
        'save before navigation',
      );
      await session.receive(Uri.parse('koi://document?id=welcome'));
      await tester.pumpAndSettle();
      expect(session.incoming.pendingCount, 1);
      expect(find.text('Draft protected: 1 pending intents'), findsOneWidget);
      expect(
        await completeCapability(tester, CapabilityLifecycle.instance.prepare),
        true,
      );
      await tester.pump();
      expect(session.tab, 'documents');
      expect(session.incoming.pendingCount, 0);
      expect(
        (await fixture.read(tester, 'incoming_intents')).toString(),
        contains('save before navigation'),
      );
      await tester.pumpWidget(const SizedBox());
      await completeCapability(tester, CapabilityLifecycle.instance.close);
      await completeCapability(tester, disposeIncomingIntents);
      await completeCapability(tester, initializeIncomingIntents);
      expect(IncomingLinkInbox.instance, isNot(same(initialInbox)));
      await completeCapability(tester, disposeIncomingIntents);
      expect(tester.takeException(), isNull);
    },
  );
}
