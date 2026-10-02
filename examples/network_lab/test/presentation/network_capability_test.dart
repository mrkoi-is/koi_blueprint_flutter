import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/network_capability.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fakes.dart';

// Web engine and browser callbacks need event-loop time; an active caret or
// indeterminate indicator is not a reason to wait for global animation idleness.
Future<void> pumpNetworkFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets(
    'connected network page switches locale without resetting query or session',
    (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      var requests = 0;
      final transport = FakeTransport((uri, method, headers, cancellation) {
        requests++;
        return HttpPayload(
          status: uri.path == '/health' ? 204 : 200,
          headers: {},
          body: uri.path == '/health'
              ? const Stream.empty()
              : Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'items': [
                        {'id': 'a', 'label': 'Fixture item'},
                      ],
                      'nextCursor': null,
                    }),
                  ),
                ),
        );
      });
      final store = MemoryTransferStore();
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NetworkCapabilityPage(
              endpoint: 'http://fixture/',
              transportFactory: () => transport,
              storeFactory: () async => store,
            ),
          ),
        ),
      );
      await pumpNetworkFrames(tester);
      await tester.enterText(find.byType(TextField), 'saved query');
      await tester.pump(const Duration(milliseconds: 301));
      await pumpNetworkFrames(tester);
      final count = requests;
      for (final entry in [
        (const Locale('en'), 'Clear query cache', 'Transfer: Idle'),
        (const Locale('zh'), '清理查询缓存', '传输：空闲'),
        (
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          '清除查詢快取',
          '傳輸：閒置',
        ),
      ]) {
        locale.value = entry.$1;
        await pumpNetworkFrames(tester);
        expect(find.text(entry.$2), findsOneWidget);
        expect(find.textContaining(entry.$3), findsOneWidget);
        expect(find.text('Fixture item'), findsOneWidget);
        expect(find.text('saved query'), findsOneWidget);
        expect(requests, count);
      }
      await tester.pumpWidget(const SizedBox());
      await pumpNetworkFrames(tester);
      expect(store.closed, true);
      expect(transport.closed, true);
    },
  );
  testWidgets(
    'network setup error follows host English Simplified and Traditional locale without recreating the owner',
    (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: buildNetworkCapabilityPage),
          ),
        ),
      );
      for (final entry in [
        (const Locale('en'), 'Retry', 'Network'),
        (const Locale('zh'), '重试', '网络'),
        (
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          '重試',
          '網路',
        ),
      ]) {
        locale.value = entry.$1;
        await pumpNetworkFrames(tester);
        expect(find.text(entry.$2), findsOneWidget);
        expect(find.text(entry.$3), findsOneWidget);
        expect(find.textContaining('NETWORK_LAB_URL'), findsOneWidget);
        await tester.tap(find.text(entry.$2));
        await pumpNetworkFrames(tester);
      }
      await tester.pumpWidget(const SizedBox());
      await pumpNetworkFrames(tester);
    },
  );
  testWidgets(
    'installable page shows missing endpoint and allows retry without starting HTTP',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: buildNetworkCapabilityPage),
        ),
      );
      await pumpNetworkFrames(tester);
      expect(find.textContaining('NETWORK_LAB_URL'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await pumpNetworkFrames(tester);
      expect(find.textContaining('NETWORK_LAB_URL'), findsOneWidget);
    },
  );
  testWidgets(
    'installable page disposal drains an in-flight store initialization',
    (tester) async {
      final opening = Completer<TransferStore>();
      final store = MemoryTransferStore();
      final transport = FakeTransport(
        (u, m, h, c) =>
            HttpPayload(status: 204, headers: {}, body: const Stream.empty()),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NetworkCapabilityPage(
            endpoint: 'http://fixture/',
            transportFactory: () => transport,
            storeFactory: () => opening.future,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      opening.complete(store);
      await pumpNetworkFrames(tester);
      expect(store.closed, true);
      expect(transport.closed, true);
      expect(tester.takeException(), isNull);
    },
  );
}
