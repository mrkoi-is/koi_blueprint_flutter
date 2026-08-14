import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/app.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  testWidgets('未登录时会进入登录页', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          _UnauthenticatedAuthRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KoiBlueprintAdminApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Koi Admin Blueprint'), findsOneWidget);
    expect(find.text('示例密码固定为 123456'), findsOneWidget);
  });
}

class _UnauthenticatedAuthRepository implements AuthRepository {
  @override
  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    return failure(const AppFailure.unauthorized(message: '测试仓库不执行登录'));
  }

  @override
  Future<void> logout() async {}

  @override
  AuthLoginResult? restoreSession() => null;
}
