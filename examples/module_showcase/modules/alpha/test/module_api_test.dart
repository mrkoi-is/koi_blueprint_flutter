import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:showcase_alpha/showcase_alpha.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

final class TestServices implements ShowcaseServices {
  final bus = StreamController<void>.broadcast(sync: true);
  final events = <String>[];
  @override
  Stream<void> get refreshes => bus.stream;
  @override
  void record(String event) => events.add(event);
}

final class TestRepository implements ShowcaseRepository {
  TestRepository(this.pending);
  final Future<String> pending;
  @override
  String get moduleId => 'alpha';
  @override
  int get generation => 9;
  @override
  Future<String> loadMessage({Duration delay = Duration.zero}) => pending;
}

void main() {
  test(
    'public factory owns timers and subscription but keeps host bus open',
    () async {
      final services = TestServices();
      final runtime = KoiModuleRuntime(
        KoiModuleCatalog([createAlphaModule(services)]),
      );
      final session = await runtime.activate('alpha');
      expect(session.capability.moduleId, 'alpha');
      expect(
        await session.capability.loadMessage(),
        'Alpha capability · session 1',
      );
      services.bus.add(null);
      expect(services.events, contains('alpha:refresh:1'));
      final pending = session.capability.loadMessage(
        delay: const Duration(hours: 1),
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<StaleModuleSessionException>()),
      );
      await runtime.disposeAsync();
      await rejected;
      expect(services.events, contains('alpha:closed:1'));
      expect(
        services.events.where((event) => event == 'alpha:accepted:1'),
        hasLength(1),
      );
      final eventCount = services.events.length;
      expect(services.bus.isClosed, isFalse);
      services.bus.add(null);
      expect(services.events, hasLength(eventCount));
      await expectLater(
        session.capability.loadMessage(),
        throwsA(isA<StaleModuleSessionException>()),
      );
      await services.bus.close();
    },
  );

  testWidgets(
    'typed route can open details and injected pending work stays visible',
    (tester) async {
      final services = TestServices();
      final module = createAlphaModule(services);
      final pending = Completer<String>();
      final router = GoRouter(
        initialLocation: const AlphaRoute().location,
        routes: module.routes,
      );
      addTearDown(() async {
        router.dispose();
        await services.bus.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            activeShowcaseRepositoryProvider.overrideWithValue(
              TestRepository(pending.future),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      expect(find.text('Alpha home page'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete('Injected capability');
      await tester.pumpAndSettle();
      expect(find.text('Injected capability'), findsOneWidget);
      await tester.tap(find.text('Alpha details'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha detail page'), findsOneWidget);
    },
  );

  testWidgets('query failure renders an error instead of empty success', (
    tester,
  ) async {
    final services = TestServices();
    final module = createAlphaModule(services);
    final pending = Completer<String>();
    final router = GoRouter(
      initialLocation: const AlphaDetailsRoute().location,
      routes: module.routes,
    );
    addTearDown(() async {
      router.dispose();
      await services.bus.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          activeShowcaseRepositoryProvider.overrideWithValue(
            TestRepository(pending.future),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('读取失败，请重试'), findsOneWidget);
  });
}
