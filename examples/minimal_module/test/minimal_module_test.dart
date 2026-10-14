import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:minimal_module/minimal_module.dart';

import 'fixtures/host_routes.dart';

void main() {
  test('public entry exports typed routes without the generated registry', () {
    expect($appRoutes, 'host route registry');
  });
  test('minimal module requires no showcase services', () async {
    final runtime = KoiModuleRuntime(KoiModuleCatalog([createMinimalModule()]));
    final session = await runtime.activate('minimal_module');
    expect(session.capability, isA<Object>());
    await runtime.disposeAsync();
    expect(session.context.isActive, isFalse);
  });

  testWidgets('typed public route is directly mountable by a host', (
    tester,
  ) async {
    final catalog = KoiModuleCatalog([createMinimalModule()]);
    final router = GoRouter(
      initialLocation: const MinimalModuleRoute().location,
      routes: catalog.routes,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Minimal Module'), findsOneWidget);
  });
}
