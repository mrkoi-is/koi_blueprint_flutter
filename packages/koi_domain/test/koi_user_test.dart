import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';

void main() {
  group('KoiUser', () {
    test('JSON roundtrip 保留全部字段并使用 snake_case', () {
      const user = KoiUser(
        id: 'user_admin',
        name: 'admin',
        companyCode: 'koi',
        role: 'super_admin',
      );

      final json = user.toJson();
      final restored = KoiUser.fromJson(json);

      expect(json, <String, dynamic>{
        'id': 'user_admin',
        'name': 'admin',
        'company_code': 'koi',
        'role': 'super_admin',
      });
      expect(restored, user);
      expect(restored.displayName, 'admin · super_admin');
    });

    test('tryFromJson 对缺失字段返回 SerializationFailure', () {
      final result = KoiUser.tryFromJson(<String, dynamic>{
        'id': 'user_admin',
        'name': 'admin',
      });

      final failure = result.match(
        (value) => value,
        (_) => throw TestFailure('缺失字段不应反序列化成功'),
      );
      expect(failure, isA<SerializationFailure>());
      expect(failure.displayMessage, '数据格式无效');
    });

    test('tryFromJson 对错误字段类型返回 SerializationFailure', () {
      final result = KoiUser.tryFromJson(<String, dynamic>{
        'id': 7,
        'name': 'admin',
        'company_code': 'koi',
        'role': 'super_admin',
      });

      expect(
        result.match((failure) => failure, (_) => null),
        isA<SerializationFailure>(),
      );
    });
  });
}
