import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_domain/koi_domain.dart';

class MockAuthDataSource {
  Future<AuthLoginResult> login({
    required String companyCode,
    required String username,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));

    return AuthLoginResult(
      user: KoiUser(
        id: 'user_$username',
        name: username,
        companyCode: companyCode,
        role: username == 'admin' ? 'super_admin' : 'operator',
      ),
      token: 'token_${companyCode}_$username',
    );
  }
}
