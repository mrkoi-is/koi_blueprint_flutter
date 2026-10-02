import 'package:device_lab/app.dart';
import 'package:device_lab/features/devices/application/device_lab_session.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:device_lab/features/devices/presentation/providers/device_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'onboarding skip, real draft protection and later setup are reachable',
    (tester) async {
      final settings = MemorySettings();
      final discovery = FakeDiscovery();
      var hostAttempts = 0;
      final session = DeviceLabSession(
        settings: settings,
        discovery: discovery,
        startHost: (_, {address = '127.0.0.1', port = 0}) async {
          hostAttempts++;
          throw UnsupportedError('Not used');
        },
        advertise: (_, _) => throw UnsupportedError('Not used'),
        importFile: (_) async => const ImportedDocument('', ''),
      );
      await session.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceSessionProvider.overrideWithValue(session)],
          child: const DeviceLabApp(locale: Locale('zh')),
        ),
      );
      await settle(tester);
      expect(find.text('首次设置 1 / 3'), findsOneWidget);
      await tester.tap(find.text('跳过，稍后设置'));
      await settle(tester);
      expect(session.state.onboarding.skipped, true);
      expect(hostAttempts, 0);
      expect(discovery.starts, 0);
      await tester.enterText(
        find.widgetWithText(TextField, '正文'),
        'Important draft',
      );
      await settle(tester);
      await session.receiveUri(Uri.parse('koi://tasks'));
      await settle(tester);
      expect(session.state.pendingIntents, 1);
      expect(session.state.dirty, true);
      settings.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await settle(tester);
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(session.state.draft, 'Important draft');
      settings.fail = false;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await settle(tester);
      expect(session.state.pendingIntents, 0);
      expect(session.state.activeTab, 'tasks');
      await tester.tap(find.byTooltip('重新配置'));
      await settle(tester);
      expect(session.state.onboarding.step, OnboardingStep.language);
      expect(find.text('首次设置 1 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      await closeSession(tester, session);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('persisted language changes the onboarding UI', (tester) async {
    final settings = MemorySettings()
      ..values = {'onboarding': const OnboardingState(language: 'en').toJson()};
    final session = DeviceLabSession(
      settings: settings,
      discovery: FakeDiscovery(),
      startHost: (_, {address = '127.0.0.1', port = 0}) =>
          throw UnsupportedError('Not used'),
      advertise: (_, _) => throw UnsupportedError('Not used'),
      importFile: (_) async => const ImportedDocument('', ''),
    );
    await session.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deviceSessionProvider.overrideWithValue(session)],
        child: const DeviceLabApp(locale: Locale('zh')),
      ),
    );
    await settle(tester);
    expect(find.text('First setup 1 / 3'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await closeSession(tester, session);
  });
}

Future<void> closeSession(WidgetTester tester, DeviceLabSession session) async {
  var closed = false;
  Object? failure;
  session.close().then(
    (_) => closed = true,
    onError: (Object error) {
      failure = error;
      closed = true;
    },
  );
  for (var i = 0; i < 20 && !closed; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(failure, isNull);
  expect(closed, true, reason: 'All resource cleanup must complete');
}
