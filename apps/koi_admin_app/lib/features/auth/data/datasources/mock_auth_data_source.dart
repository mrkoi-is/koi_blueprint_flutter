import 'package:koi_admin_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_domain/koi_domain.dart';

final class MockAuthDataSource implements AuthDataSource {
  @override
  Future<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    if (password != '123456') {
      throw const InvalidCredentialsException('示例密码固定为 123456');
    }

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
