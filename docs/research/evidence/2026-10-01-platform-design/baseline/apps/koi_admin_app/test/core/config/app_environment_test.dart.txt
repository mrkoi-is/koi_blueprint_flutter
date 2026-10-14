import 'package:flutter_test/flutter_test.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';

void main() {
  group('AppEnvironment.fromName', () {
    test('dev 是唯一允许 Mock 认证的环境', () {
      final environment = AppEnvironment.fromName('dev');

      expect(environment.flavor, AppFlavor.dev);
      expect(environment.usesMockAuth, isTrue);
      expect(environment.enableNetworkLog, isTrue);
    });

    test('staging 和 prod 关闭 Mock 认证及网络日志', () {
      for (final name in ['staging', 'prod']) {
        final environment = AppEnvironment.fromName(name);

        expect(environment.usesMockAuth, isFalse, reason: name);
        expect(environment.enableNetworkLog, isFalse, reason: name);
      }
    });

    test('未知环境不会静默降级到 dev', () {
      expect(() => AppEnvironment.fromName('production'), throwsArgumentError);
    });
  });

  group('AppEnvironment.resolve', () {
    test('非 release 未指定环境时使用 dev', () {
      expect(
        AppEnvironment.resolve('', isRelease: false).flavor,
        AppFlavor.dev,
      );
    });

    test('release 未指定环境时拒绝启动', () {
      expect(
        () => AppEnvironment.resolve('', isRelease: true),
        throwsStateError,
      );
    });

    test('release 明确指定 dev 时拒绝 Mock 认证', () {
      expect(
        () => AppEnvironment.resolve('dev', isRelease: true),
        throwsStateError,
      );
    });

    test('release 明确指定 prod 时允许进入后续配置校验', () {
      expect(
        AppEnvironment.resolve('prod', isRelease: true).flavor,
        AppFlavor.prod,
      );
    });

    test('release 明确指定 staging 时允许进入后续配置校验', () {
      expect(
        AppEnvironment.resolve('staging', isRelease: true).flavor,
        AppFlavor.staging,
      );
    });
  });
}
