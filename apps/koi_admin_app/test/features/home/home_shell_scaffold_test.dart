import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:koi_admin_app/features/home/presentation/widgets/home_shell_scaffold.dart';

void main() {
  for (final width in [320.0, 600.0, 1024.0, 1440.0]) {
    testWidgets('Admin uses local width $width and pins utility settings', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const HomeShellScaffold(
                currentIndex: 1,
                title: '工作区设置',
                child: Text('设置内容'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(NavigationRail),
        width >= 600 ? findsOneWidget : findsNothing,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('设置'), findsOneWidget);
      expect(find.text('工作区设置'), findsOneWidget);
      expect(
        find.byTooltip('返回总览'),
        width < 600 ? findsOneWidget : findsNothing,
      );
      if (width >= 600) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          isNull,
        );
        expect(tester.getTopLeft(find.byTooltip('设置')).dy, greaterThan(700));
      }
      expect(tester.getSize(find.byType(KoiWorkbenchFrame)).width, width);
      expect(tester.takeException(), isNull);
    });
  }
}
