import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/features/home/presentation/screens/dashboard_page.dart';
import 'package:koi_ui/koi_ui.dart';

void main() {
  for (final width in [375.0, 390.0, 1200.0]) {
    testWidgets('dashboard cards fit a $width pixel viewport', (tester) async {
      tester.view.physicalSize = Size(width, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const DashboardPage()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
