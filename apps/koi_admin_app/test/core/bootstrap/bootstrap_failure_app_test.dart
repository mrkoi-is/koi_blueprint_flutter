import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/core/bootstrap/bootstrap_failure_app.dart';

void main() {
  testWidgets('启动失败时显示安全的兜底页面', (tester) async {
    await tester.pumpWidget(
      BootstrapFailureApp(error: StateError('invalid environment')),
    );

    expect(find.text('应用初始化失败'), findsOneWidget);
    expect(find.text('请检查环境配置与网络初始化设置后重新启动。'), findsOneWidget);
  });
}
