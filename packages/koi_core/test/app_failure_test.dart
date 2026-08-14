import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  group('AppFailure', () {
    test('displayMessage 返回各失败类型的可展示文案', () {
      const failures = <AppFailure>[
        AppFailure.validation(message: '账号不能为空'),
        AppFailure.network(message: '网络暂不可用'),
        AppFailure.unauthorized(message: '请重新登录'),
        AppFailure.serialization(message: '响应数据无效'),
        AppFailure.unknown(message: '服务暂不可用'),
      ];

      expect(failures.map((failure) => failure.displayMessage), <String>[
        '账号不能为空',
        '网络暂不可用',
        '请重新登录',
        '响应数据无效',
        '服务暂不可用',
      ]);
    });

    test('UnauthorizedFailure 有默认提示', () {
      const failure = AppFailure.unauthorized();

      expect(failure.displayMessage, '登录态已失效，请重新登录');
    });

    test('SerializationFailure 有安全的默认提示', () {
      final failure = AppFailure.serialization(
        error: _SensitiveError(),
        stackTrace: StackTrace.fromString('sensitive-stack-trace'),
      );

      expect(failure, isA<SerializationFailure>());
      expect(failure.displayMessage, '数据格式无效');
    });

    test('toString 不暴露原始错误或堆栈', () {
      final failures = <AppFailure>[
        AppFailure.serialization(
          error: _SensitiveError(),
          stackTrace: StackTrace.fromString('sensitive-stack-trace'),
        ),
        AppFailure.unknown(
          message: '操作失败',
          error: _SensitiveError(),
          stackTrace: StackTrace.fromString('sensitive-stack-trace'),
        ),
      ];

      for (final failure in failures) {
        expect(failure.toString(), isNot(contains(_SensitiveError.value)));
        expect(failure.toString(), isNot(contains('sensitive-stack-trace')));
      }
    });
  });

  group('Result helpers', () {
    test('success 创建 Right', () {
      final result = success(42);

      expect(result.isRight(), isTrue);
      expect(
        result.match((failure) => failure.displayMessage, (value) => value),
        42,
      );
    });

    test('failure 创建 Left', () {
      const appFailure = AppFailure.validation(message: '输入无效');
      final result = failure<int>(appFailure);

      expect(result.isLeft(), isTrue);
      expect(result.match((value) => value, (_) => null), same(appFailure));
    });
  });
}

class _SensitiveError implements Exception {
  static const value = 'raw-password=never-print-this';

  @override
  String toString() => value;
}
