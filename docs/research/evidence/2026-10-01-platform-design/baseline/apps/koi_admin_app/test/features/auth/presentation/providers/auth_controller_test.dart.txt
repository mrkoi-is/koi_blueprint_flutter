import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_auth/koi_auth.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';

void main() {
  group('AuthController', () {
    test('登录期间进入 loading，成功后进入 authenticated', () async {
      final loginCompleter = Completer<Either<AppFailure, AuthLoginResult>>();
      final repository = _FakeAuthRepository(
        loginResult: loginCompleter.future,
      );
      final container = _createContainer(repository);
      final controller = container.read(authControllerProvider.notifier);

      final loginFuture = controller.login(
        companyCode: 'koi',
        username: 'admin',
        password: '123456',
      );

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.loading(),
      );

      loginCompleter.complete(right(_adminLoginResult));
      await loginFuture;

      expect(
        container.read(authControllerProvider),
        AuthSession<KoiUser>.authenticated(
          user: _adminLoginResult.user,
          token: _adminLoginResult.token,
        ),
      );
      expect(repository.loginCalls, 1);
    });

    test('登录失败后进入 failure 并保留可展示消息', () async {
      const failure = AppFailure.unauthorized(message: '账号或密码错误');
      final repository = _FakeAuthRepository(
        loginResult: Future.value(left(failure)),
      );
      final container = _createContainer(repository);
      final controller = container.read(authControllerProvider.notifier);

      final loginFuture = controller.login(
        companyCode: 'koi',
        username: 'admin',
        password: 'wrong-password',
      );

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.loading(),
      );
      await loginFuture;

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.failure(message: '账号或密码错误'),
      );
    });

    test('logout 调用仓库并进入 unauthenticated', () async {
      final repository = _FakeAuthRepository(
        restoredSession: _adminLoginResult,
        loginResult: Future.value(right(_adminLoginResult)),
      );
      final container = _createContainer(repository);
      final controller = container.read(authControllerProvider.notifier);
      expect(
        container.read(authControllerProvider),
        AuthSession<KoiUser>.authenticated(
          user: _adminLoginResult.user,
          token: _adminLoginResult.token,
        ),
      );

      await controller.logout();

      expect(repository.logoutCalls, 1);
      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.unauthenticated(),
      );
    });

    test('logout 会让尚未完成的 login 结果失效', () async {
      final loginCompleter = Completer<Either<AppFailure, AuthLoginResult>>();
      final repository = _FakeAuthRepository(
        loginResult: loginCompleter.future,
      );
      final container = _createContainer(repository);
      final controller = container.read(authControllerProvider.notifier);

      final loginFuture = controller.login(
        companyCode: 'koi',
        username: 'admin',
        password: '123456',
      );
      await controller.logout();
      loginCompleter.complete(right(_adminLoginResult));
      await loginFuture;

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.unauthenticated(),
      );
      expect(repository.logoutCalls, 1);
    });

    test('handleUnauthorized 清理仓库并进入 unauthenticated', () async {
      final repository = _FakeAuthRepository(
        restoredSession: _adminLoginResult,
        loginResult: Future.value(right(_adminLoginResult)),
      );
      final container = _createContainer(repository);

      await container
          .read(authControllerProvider.notifier)
          .handleUnauthorized();

      expect(repository.logoutCalls, 1);
      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.unauthenticated(),
      );
    });
  });
}

final AuthLoginResult _adminLoginResult = AuthLoginResult(
  user: const KoiUser(
    id: 'user_admin',
    name: 'admin',
    companyCode: 'koi',
    role: 'super_admin',
  ),
  token: 'token_koi_admin',
);

ProviderContainer _createContainer(AuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  final subscription = container.listen<AuthSession<KoiUser>>(
    authControllerProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.loginResult, this.restoredSession});

  final FutureResult<AuthLoginResult> loginResult;
  final AuthLoginResult? restoredSession;
  int loginCalls = 0;
  int logoutCalls = 0;

  @override
  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) {
    loginCalls += 1;
    return loginResult;
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  AuthLoginResult? restoreSession() => restoredSession;
}
