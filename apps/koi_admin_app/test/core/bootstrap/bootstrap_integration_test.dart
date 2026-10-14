import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/bootstrap.dart';
import 'package:koi_admin_app/features/auth/presentation/screens/login_page.dart';
import 'package:koi_admin_app/features/home/presentation/screens/dashboard_page.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';

void main() {
  testWidgets('dev bootstrap wires auth, router, and the demo login', (
    tester,
  ) async {
    final tokenStorage = KoiMemoryTokenSession();
    final container = await bootstrap(tokenStorage: tokenStorage);
    addTearDown(() async {
      container.dispose();
      await disposeKoiApi();
    });

    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    final loginButton = find.text('进入控制台');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(tokenStorage.getToken(), 'token_KOI_admin');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
