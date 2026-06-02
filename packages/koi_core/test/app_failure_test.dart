import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  test('AppFailure.displayMessage 返回可展示文案', () {
    const failure = AppFailure.validation(message: '账号不能为空');

    expect(failure.displayMessage, '账号不能为空');
  });

  test('UnauthorizedFailure 有默认提示', () {
    const failure = AppFailure.unauthorized();

    expect(failure.displayMessage, '登录态已失效，请重新登录');
  });
}
