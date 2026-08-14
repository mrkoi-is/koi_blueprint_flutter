import 'package:flutter_test/flutter_test.dart';
import 'package:koi_auth/koi_auth.dart';

void main() {
  group('AuthSession', () {
    test('各状态只在 authenticated 时标记为已登录', () {
      const unauthenticated = AuthSession<String>.unauthenticated();
      const loading = AuthSession<String>.loading();
      const authenticated = AuthSession<String>.authenticated(
        user: 'admin',
        token: 'token',
      );
      const failure = AuthSession<String>.failure(message: '登录失败');

      expect(unauthenticated.isAuthenticated, isFalse);
      expect(loading.isAuthenticated, isFalse);
      expect(authenticated.isAuthenticated, isTrue);
      expect(failure.isAuthenticated, isFalse);
    });

    test('authenticated 暴露用户和令牌给模式匹配', () {
      const session = AuthSession<String>.authenticated(
        user: 'admin',
        token: 'token_koi_admin',
      );

      final credentials = session.maybeWhen(
        authenticated: (user, token) => (user: user, token: token),
        orElse: () => null,
      );

      expect(credentials?.user, 'admin');
      expect(credentials?.token, 'token_koi_admin');
    });

    test('toString 不泄露认证令牌', () {
      const secretToken = 'secret-token-that-must-not-leak';
      const session = AuthSession<String>.authenticated(
        user: 'admin',
        token: secretToken,
      );

      expect(session.toString(), isNot(contains(secretToken)));
    });

    test('failure 保留可展示消息', () {
      const session = AuthSession<String>.failure(message: '账号或密码错误');

      final message = session.maybeWhen(
        failure: (value) => value,
        orElse: () => null,
      );

      expect(message, '账号或密码错误');
    });
  });
}
