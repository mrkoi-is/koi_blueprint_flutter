import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/app.dart';
import 'package:module_showcase/bootstrap.dart';
import 'package:module_showcase/core/providers/module_providers.dart';
import 'package:showcase_alpha/showcase_alpha.dart';
import 'package:showcase_beta/showcase_beta.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

Future<void> settleResources(WidgetTester tester) async {
  await tester.pump();
  // Dart's already-completed stream cancellation Future is rooted outside the
  // fake clock. Drain that completion before the next widget frame.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('query deep link activates its module before first frame', (
    tester,
  ) async {
    final bootstrap = await ShowcaseBootstrap.create(
      initialLocation: '/beta?tab=1',
    );
    await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(bootstrap.runtime.state.session?.moduleId, 'beta');
    expect(
      bootstrap.router.routeInformationProvider.value.uri.toString(),
      '/beta?tab=1',
    );
    await tester.pumpWidget(const SizedBox());
    await settleResources(tester);
    await bootstrap.disposeAsync();
  });

  testWidgets('detail deep link retains query and fragment', (tester) async {
    final bootstrap = await ShowcaseBootstrap.create(
      initialLocation: '/beta/details?tab=1#section',
    );
    await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(bootstrap.runtime.state.session?.moduleId, 'beta');
    expect(find.text('Beta detail page'), findsOneWidget);
    expect(
      bootstrap.router.routeInformationProvider.value.uri.toString(),
      '/beta/details?tab=1#section',
    );
    await tester.pumpWidget(const SizedBox());
    await settleResources(tester);
    await bootstrap.disposeAsync();
  });

  test('similarly prefixed path does not select a different module', () async {
    final bootstrap = await ShowcaseBootstrap.create(
      initialLocation: '/beta_extra',
    );
    expect(bootstrap.runtime.state.session?.moduleId, 'alpha');
    await bootstrap.disposeAsync();
  });

  testWidgets('failed module switch displays failure and supports retry', (
    tester,
  ) async {
    final bootstrap = await ShowcaseBootstrap.create(
      buildModules: (shared) {
        final beta = createBetaModule(shared);
        return [
          createAlphaModule(shared),
          KoiModule<ShowcaseRepository>(
            id: beta.id,
            routes: beta.routes,
            navigation: beta.navigation,
            createSession: (_) =>
                throw StateError('expected initialization failure'),
          ),
        ];
      },
    );
    await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换 Beta'));
    await settleResources(tester);
    expect(find.textContaining('装载失败：'), findsOneWidget);
    expect(find.text('请选择模块重试'), findsOneWidget);
    expect(bootstrap.runtime.state.session, isNull);
    expect(bootstrap.services.isClosed, isFalse);
    await tester.tap(find.text('切换 Alpha'));
    await settleResources(tester);
    expect(find.text('Alpha home page'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settleResources(tester);
    await bootstrap.disposeAsync();
  });

  test(
    'bootstrap activates direct module page and replaces public capability',
    () async {
      final app = await ShowcaseBootstrap.create(
        initialLocation: '/beta/details',
      );
      final router = app.router;
      final first = app.container.read(activeShowcaseRepositoryProvider);
      expect(first.moduleId, 'beta');
      expect(await first.loadMessage(), 'Beta capability · session 1');
      final pending = first.loadMessage(delay: const Duration(hours: 1));
      final rejected = expectLater(
        pending,
        throwsA(isA<StaleModuleSessionException>()),
      );
      await app.runtime.activate('alpha');
      await rejected;
      final second = app.container.read(activeShowcaseRepositoryProvider);
      expect(second.moduleId, 'alpha');
      expect(second.generation, greaterThan(first.generation));
      expect(app.router, same(router));
      expect(app.services.isClosed, isFalse);
      app.services.refresh();
      expect(app.services.events, contains('alpha:refresh:2'));
      expect(app.services.events, isNot(contains('beta:refresh:1')));
      expect(app.services.events, isNot(contains('beta:accepted:2')));
      final disposal = app.disposeAsync();
      expect(app.disposeAsync(), same(disposal));
      await disposal;
      expect(app.services.isClosed, isTrue);
      expect(app.services.events.last, 'alpha:closed:2');
      await app.services.close();
      expect(() => app.services.record('too late'), throwsStateError);
    },
  );

  test(
    'host controls reject old result and report unknown module failure',
    () async {
      final app = await ShowcaseBootstrap.create();
      final controls = app.container.read(moduleControlsProvider.notifier);
      await controls.demonstrateStaleResult();
      expect(app.runtime.state.session?.moduleId, 'beta');
      expect(app.container.read(moduleControlsProvider), '旧会话结果已拒绝');
      await controls.select('missing');
      expect(app.container.read(moduleControlsProvider), startsWith('模块切换失败：'));
      await Future.wait([controls.select('alpha'), controls.select('beta')]);
      expect(app.runtime.state.session?.moduleId, 'beta');
      final switching = controls.select('alpha');
      await controls.demonstrateStaleResult();
      await switching;
      await app.disposeAsync();
    },
  );

  test('runtime injection is required and switching does not return old capability', () async {
    final missing = ProviderContainer(retry: (_, _) => null);
    expect(() => missing.read(moduleRuntimeProvider), throwsA(anything));
    missing.dispose();
    final app = await ShowcaseBootstrap.create();
    // Watch the bridge so that invalidation reaches all dependents immediately.
    final subscription = app.container.listen(
      moduleSnapshotProvider,
      (_, _) {},
    );
    final switching = app.runtime.activate('beta');
    expect(
      () => app.container.read(activeShowcaseRepositoryProvider),
      throwsA(anything),
    );
    await switching;
    expect(
      app.container.read(activeShowcaseRepositoryProvider).moduleId,
      'beta',
    );
    subscription.close();
    await app.disposeAsync();
  });

  testWidgets(
    'direct detail page and switching work with one router and no home prerequisite',
    (tester) async {
      final bootstrap = await ShowcaseBootstrap.create(
        initialLocation: '/beta/details',
      );
      final router = bootstrap.router;
      await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
      await tester.pumpAndSettle();
      expect(find.text('Beta detail page'), findsOneWidget);
      expect(find.text('Beta home page'), findsNothing);
      expect(find.textContaining('Beta capability'), findsOneWidget);
      await tester.tap(find.text('切换 Alpha'));
      await settleResources(tester);
      router.go(const AlphaDetailsRoute().location);
      await tester.pumpAndSettle();
      expect(bootstrap.router, same(router));
      expect(find.text('Alpha detail page'), findsOneWidget);
      expect(find.textContaining('Alpha capability'), findsOneWidget);
      await tester.tap(find.text('延迟读取后立即切换'));
      await settleResources(tester);
      expect(find.text('旧会话结果已拒绝'), findsOneWidget);
      expect(find.text('Beta home page'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settleResources(tester);
      await bootstrap.disposeAsync();
      expect(bootstrap.services.isClosed, isTrue);
    },
  );

  testWidgets('inactive module navigation redirects to current active module', (
    tester,
  ) async {
    final bootstrap = await ShowcaseBootstrap.create(initialLocation: '/');
    await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(find.text('Alpha home page'), findsOneWidget);
    bootstrap.router.go('/beta/details');
    await tester.pumpAndSettle();
    expect(find.text('Alpha home page'), findsOneWidget);
    expect(find.text('Beta detail page'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settleResources(tester);
    await bootstrap.disposeAsync();
  });
}
