import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:koi_admin_app/app.dart';
import 'package:koi_admin_app/core/router/app_router.dart';
import 'package:koi_admin_app/core/router/app_routes.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_admin_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:koi_admin_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:koi_admin_app/features/auth/presentation/screens/login_page.dart';
import 'package:koi_admin_app/features/home/presentation/screens/dashboard_page.dart';
import 'package:koi_auth/koi_auth.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';

const _testUser = KoiUser(
  id: 'user_admin',
  name: 'admin',
  companyCode: 'KOI',
  role: 'super_admin',
);

const _testLoginResult = AuthLoginResult(
  user: _testUser,
  token: 'token_KOI_admin',
);

void main() {
  group('appRouterProvider', () {
    test('认证状态变化期间保持同一个 GoRouter 实例', () async {
      final repository = _ControllableAuthRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);

      var routerEmissions = 0;
      final routerSubscription = container.listen(
        appRouterProvider,
        (previous, next) => routerEmissions += 1,
        fireImmediately: true,
      );
      addTearDown(routerSubscription.close);

      final router = routerSubscription.read();
      final controller = container.read(authControllerProvider.notifier);

      final failedLogin = controller.login(
        companyCode: _testUser.companyCode,
        username: _testUser.name,
        password: 'wrong-password',
      );

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.loading(),
      );
      expect(routerSubscription.read(), same(router));

      repository.completeFailure('账号或密码错误');
      await failedLogin;

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.failure(message: '账号或密码错误'),
      );
      expect(routerSubscription.read(), same(router));

      final successfulLogin = controller.login(
        companyCode: _testUser.companyCode,
        username: _testUser.name,
        password: '123456',
      );

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.loading(),
      );
      expect(routerSubscription.read(), same(router));

      repository.completeSuccess();
      await successfulLogin;

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.authenticated(
          user: _testUser,
          token: 'token_KOI_admin',
        ),
      );
      expect(routerSubscription.read(), same(router));

      await controller.logout();

      expect(
        container.read(authControllerProvider),
        const AuthSession<KoiUser>.unauthenticated(),
      );
      expect(routerSubscription.read(), same(router));
      expect(routerEmissions, 1);
    });
  });

  group('路由认证回归', () {
    testWidgets('未登录访问受保护页面会重定向到登录页', (tester) async {
      final repository = _ControllableAuthRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoiBlueprintAdminApp(),
        ),
      );

      final router = container.read(appRouterProvider);
      router.go(const DashboardRoute().location);
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        const LoginRoute().location,
      );
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
    });

    testWidgets('登录成功后离开登录页，退出后返回登录页', (tester) async {
      final repository = _ControllableAuthRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KoiBlueprintAdminApp(),
        ),
      );

      final router = container.read(appRouterProvider);
      final controller = container.read(authControllerProvider.notifier);

      router.go(const LoginRoute().location);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      final failedLogin = controller.login(
        companyCode: _testUser.companyCode,
        username: _testUser.name,
        password: 'wrong-password',
      );
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        const LoginRoute().location,
      );
      expect(find.text('登录中...'), findsOneWidget);

      repository.completeFailure('账号或密码错误');
      await failedLogin;
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        const LoginRoute().location,
      );
      expect(find.byType(LoginPage), findsOneWidget);

      final successfulLogin = controller.login(
        companyCode: _testUser.companyCode,
        username: _testUser.name,
        password: '123456',
      );
      repository.completeSuccess();
      await successfulLogin;
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        const DashboardRoute().location,
      );
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);

      await controller.logout();
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        const LoginRoute().location,
      );
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
    });
  });
}

ProviderContainer _createContainer(AuthRepository repository) {
  return ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
}

class _ControllableAuthRepository implements AuthRepository {
  Completer<Result<AuthLoginResult>>? _pendingLogin;

  @override
  AuthLoginResult? restoreSession() => null;

  @override
  FutureResult<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) {
    if (_pendingLogin != null) {
      throw StateError('已有登录请求尚未完成');
    }

    final completer = Completer<Result<AuthLoginResult>>();
    _pendingLogin = completer;
    return completer.future;
  }

  void completeFailure(String message) {
    _takePendingLogin().complete(
      left(AppFailure.unauthorized(message: message)),
    );
  }

  void completeSuccess() {
    _takePendingLogin().complete(right(_testLoginResult));
  }

  @override
  Future<void> logout() async {}

  Completer<Result<AuthLoginResult>> _takePendingLogin() {
    final completer = _pendingLogin;
    if (completer == null) {
      throw StateError('当前没有待完成的登录请求');
    }
    _pendingLogin = null;
    return completer;
  }
}
