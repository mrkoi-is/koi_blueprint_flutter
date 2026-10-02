import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/app.dart';
import 'package:module_showcase/bootstrap.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real Alpha/Beta injection declares operations and configuration recovers in the same router',
    (tester) async {
      final bootstrap = await ShowcaseBootstrap.create();
      await tester.pumpWidget(ModuleShowcaseApp(bootstrap: bootstrap));
      await settle(tester);
      final router = bootstrap.router;
      expect(
        bootstrap.runtime.catalog.modules.every(
          (module) => module.capabilities.contains('message.read'),
        ),
        isTrue,
      );
      final alpha = bootstrap.container.read(activeShowcaseRepositoryProvider);
      expect(
        await tester.runAsync(alpha.loadMessage),
        contains('Alpha capability'),
      );
      await tester.tap(find.text('停用 Beta 配置'));
      await settle(tester);
      await tester.tap(find.text('切换 Beta'));
      await settle(tester);
      expect(bootstrap.runtime.state.session, isNull);
      expect(
        bootstrap.runtime.state.availability?.status,
        CapabilityStatus.unavailable,
      );
      expect(find.text('Beta 尚未配置，请启用后重试'), findsOneWidget);
      expect(bootstrap.services.isClosed, isFalse);
      await tester.tap(find.text('启用 Beta 配置'));
      await settle(tester);
      await tester.tap(find.text('切换 Beta'));
      await settle(tester);
      expect(find.text('Beta home page'), findsOneWidget);
      final beta = bootstrap.container.read(activeShowcaseRepositoryProvider);
      expect(
        await tester.runAsync(beta.loadMessage),
        contains('Beta capability'),
      );
      expect(bootstrap.router, same(router));
      expect(alpha, isNot(same(beta)));
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await bootstrap.disposeAsync();
    },
  );
}
