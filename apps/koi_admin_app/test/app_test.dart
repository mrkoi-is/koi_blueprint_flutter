import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/app.dart';
import 'package:koi_admin_app/core/providers/bootstrap_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('未登录时会进入登录页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KoiBlueprintAdminApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Koi Admin Blueprint'), findsOneWidget);
    expect(find.text('示例密码固定为 123456'), findsOneWidget);
  });
}
