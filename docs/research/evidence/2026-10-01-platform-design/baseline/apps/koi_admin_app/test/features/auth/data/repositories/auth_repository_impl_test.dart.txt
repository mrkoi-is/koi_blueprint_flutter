import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:koi_admin_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:koi_admin_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:koi_admin_app/features/auth/domain/entities/auth_login_result.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';

void main() {
  group('AuthRepositoryImpl', () {
    group('login', () {
      const invalidInputs =
          <
            ({
              String companyCode,
              String username,
              String password,
              String label,
            })
          >[
            (
              companyCode: '',
              username: 'admin',
              password: '123456',
              label: '公司编码为空',
            ),
            (
              companyCode: 'koi',
              username: '',
              password: '123456',
              label: '账号为空',
            ),
            (
              companyCode: 'koi',
              username: 'admin',
              password: '',
              label: '密码为空',
            ),
          ];

      for (final input in invalidInputs) {
        test('${input.label}时返回校验失败', () async {
          final repository = _createRepository();

          final result = await repository.login(
            companyCode: input.companyCode,
            username: input.username,
            password: input.password,
          );

          final failure = result.match(
            (value) => value,
            (_) => throw TestFailure('空输入不应登录成功'),
          );
          expect(failure, isA<ValidationFailure>());
          expect(failure.displayMessage, '公司编码、账号和密码不能为空');
          expect(repository.restoreSession(), isNull);
        });
      }

      test('密码错误时返回未授权失败且不保存会话', () async {
        final repository = _createRepository();

        final result = await repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: 'wrong-password',
        );

        final failure = result.match(
          (value) => value,
          (_) => throw TestFailure('错误密码不应登录成功'),
        );
        expect(failure, isA<UnauthorizedFailure>());
        expect(failure.displayMessage, '示例密码固定为 123456');
        expect(repository.restoreSession(), isNull);
      });

      test('成功登录后恢复的会话完整保留用户和令牌', () async {
        final tokenSession = KoiMemoryTokenSession();
        final repository = _createRepository(tokenSession: tokenSession);

        final result = await repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: '123456',
        );
        final loginSession = result.match(
          (failure) => throw TestFailure('登录应成功：${failure.displayMessage}'),
          (session) => session,
        );

        final restoredSession = repository.restoreSession();

        expect(restoredSession, isNotNull);
        expect(restoredSession, loginSession);
        expect(restoredSession?.user.id, 'user_admin');
        expect(restoredSession?.user.role, 'super_admin');
        expect(restoredSession?.token, 'token_koi_admin');
        expect(tokenSession.getToken(), 'token_koi_admin');
      });

      test('令牌写入失败时登录失败且不会恢复会话', () async {
        final repository = AuthRepositoryImpl(
          dataSource: MockAuthDataSource(),
          tokenSession: _FailingTokenSession(),
        );

        final result = await repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: '123456',
        );

        final failure = result.match(
          (value) => value,
          (_) => throw TestFailure('会话持久化失败时不应登录成功'),
        );
        expect(failure, isA<UnknownFailure>());
        expect(repository.restoreSession(), isNull);
      });

      test('logout 会阻止较晚完成的 login 重新写入令牌', () async {
        final dataSource = _ControllableAuthDataSource();
        final tokenSession = KoiMemoryTokenSession();
        final repository = AuthRepositoryImpl(
          dataSource: dataSource,
          tokenSession: tokenSession,
        );

        final login = repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: '123456',
        );
        await dataSource.loginStarted.future;

        final logout = repository.logout();
        dataSource.completeSuccess();

        final loginResult = await login;
        await logout;

        expect(loginResult.isLeft(), isTrue);
        expect(repository.restoreSession(), isNull);
        expect(tokenSession.hasToken, isFalse);
      });

      test('logout 会等待进行中的令牌写入并最终清空会话', () async {
        final tokenSession = _DelayedSaveTokenSession();
        final repository = AuthRepositoryImpl(
          dataSource: MockAuthDataSource(),
          tokenSession: tokenSession,
        );

        final login = repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: '123456',
        );
        await tokenSession.saveStarted.future;

        final logout = repository.logout();
        tokenSession.releaseSave.complete();

        final loginResult = await login;
        await logout;

        expect(loginResult.isLeft(), isTrue);
        expect(repository.restoreSession(), isNull);
        expect(tokenSession.hasToken, isFalse);
      });

      test('旧 login 晚到异常不会清除新 login 建立的会话', () async {
        final dataSource = _ConcurrentAuthDataSource();
        final tokenSession = KoiMemoryTokenSession();
        final repository = AuthRepositoryImpl(
          dataSource: dataSource,
          tokenSession: tokenSession,
        );

        final oldLogin = repository.login(
          companyCode: 'koi',
          username: 'old',
          password: '123456',
        );
        await dataSource.oldStarted.future;

        final newLogin = repository.login(
          companyCode: 'koi',
          username: 'new',
          password: '123456',
        );
        await dataSource.newStarted.future;
        dataSource.completeNewSuccess();
        expect((await newLogin).isRight(), isTrue);

        dataSource.completeOldFailure();
        expect((await oldLogin).isLeft(), isTrue);

        expect(repository.restoreSession()?.user.name, 'new');
        expect(repository.restoreSession()?.token, 'token_koi_new');
        expect(tokenSession.getToken(), 'token_koi_new');
      });

      test('较新的空字段 login 会撤销正在进行的旧 login', () async {
        final dataSource = _ControllableAuthDataSource();
        final tokenSession = KoiMemoryTokenSession();
        final repository = AuthRepositoryImpl(
          dataSource: dataSource,
          tokenSession: tokenSession,
        );

        final oldLogin = repository.login(
          companyCode: 'koi',
          username: 'admin',
          password: '123456',
        );
        await dataSource.loginStarted.future;

        final invalidLogin = await repository.login(
          companyCode: 'koi',
          username: '',
          password: '123456',
        );
        dataSource.completeSuccess();

        expect(invalidLogin.isLeft(), isTrue);
        expect((await oldLogin).isLeft(), isTrue);
        expect(repository.restoreSession(), isNull);
        expect(tokenSession.hasToken, isFalse);
      });
    });

    test('logout 清除会话后不可恢复', () async {
      final tokenSession = KoiMemoryTokenSession();
      final repository = _createRepository(tokenSession: tokenSession);
      final result = await repository.login(
        companyCode: 'koi',
        username: 'admin',
        password: '123456',
      );
      expect(result.isRight(), isTrue);
      expect(repository.restoreSession(), isNotNull);

      await repository.logout();

      expect(repository.restoreSession(), isNull);
      expect(tokenSession.hasToken, isFalse);
    });

    test('令牌被外部清除后现有内存会话失效', () async {
      final tokenSession = KoiMemoryTokenSession();
      final repository = _createRepository(tokenSession: tokenSession);
      final result = await repository.login(
        companyCode: 'koi',
        username: 'admin',
        password: '123456',
      );
      expect(result.isRight(), isTrue);
      expect(repository.restoreSession(), isNotNull);

      await tokenSession.clearToken();

      expect(repository.restoreSession(), isNull);
    });

    test('只有令牌的新仓库实例会撤销缺失用户的孤立令牌', () async {
      final tokenSession = KoiMemoryTokenSession();
      final firstRepository = _createRepository(tokenSession: tokenSession);
      final result = await firstRepository.login(
        companyCode: 'koi',
        username: 'admin',
        password: '123456',
      );
      expect(result.isRight(), isTrue);
      expect(tokenSession.hasToken, isTrue);

      final newRepository = _createRepository(tokenSession: tokenSession);

      expect(newRepository.restoreSession(), isNull);
      expect(newRepository.tokenSession.hasToken, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(tokenSession.hasToken, isFalse);
    });
  });
}

AuthRepositoryImpl _createRepository({KoiTokenSession? tokenSession}) {
  return AuthRepositoryImpl(
    dataSource: MockAuthDataSource(),
    tokenSession: tokenSession ?? KoiMemoryTokenSession(),
  );
}

class _FailingTokenSession implements KoiTokenSession {
  @override
  bool get hasToken => false;

  @override
  Future<void> clearToken() async {}

  @override
  String? getToken() => null;

  @override
  Future<void> saveToken(String token) async {
    throw StateError('token store unavailable');
  }
}

class _ControllableAuthDataSource implements AuthDataSource {
  final loginStarted = Completer<void>();
  final _result = Completer<AuthLoginResult>();

  @override
  Future<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) {
    loginStarted.complete();
    return _result.future;
  }

  void completeSuccess() {
    _result.complete(
      const AuthLoginResult(
        user: KoiUser(
          id: 'user_admin',
          name: 'admin',
          companyCode: 'koi',
          role: 'super_admin',
        ),
        token: 'token_koi_admin',
      ),
    );
  }
}

class _DelayedSaveTokenSession implements KoiTokenSession {
  final saveStarted = Completer<void>();
  final releaseSave = Completer<void>();
  String? _token;

  @override
  bool get hasToken => _token != null;

  @override
  String? getToken() => _token;

  @override
  Future<void> saveToken(String token) async {
    saveStarted.complete();
    await releaseSave.future;
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }
}

class _ConcurrentAuthDataSource implements AuthDataSource {
  final oldStarted = Completer<void>();
  final newStarted = Completer<void>();
  final _oldResult = Completer<AuthLoginResult>();
  final _newResult = Completer<AuthLoginResult>();

  @override
  Future<AuthLoginResult> login({
    required String companyCode,
    required String username,
    required String password,
  }) {
    if (username == 'old') {
      oldStarted.complete();
      return _oldResult.future;
    }
    newStarted.complete();
    return _newResult.future;
  }

  void completeNewSuccess() {
    _newResult.complete(
      const AuthLoginResult(
        user: KoiUser(
          id: 'user_new',
          name: 'new',
          companyCode: 'koi',
          role: 'admin',
        ),
        token: 'token_koi_new',
      ),
    );
  }

  void completeOldFailure() {
    _oldResult.completeError(StateError('旧请求失败'));
  }
}
