import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_domain/koi_domain.dart';

void main() {
  group('KoiWorkspaceTile', () {
    test('JSON roundtrip 保留全部字段', () {
      const tile = KoiWorkspaceTile(
        title: '订单中心',
        description: '查看和处理全部订单',
        category: 'commerce',
        highlighted: true,
      );

      final json = tile.toJson();
      final restored = KoiWorkspaceTile.fromJson(json);

      expect(json, <String, dynamic>{
        'title': '订单中心',
        'description': '查看和处理全部订单',
        'category': 'commerce',
        'highlighted': true,
      });
      expect(restored, tile);
    });

    test('fromJson 缺少 highlighted 时使用 false', () {
      final tile = KoiWorkspaceTile.fromJson(<String, dynamic>{
        'title': '订单中心',
        'description': '查看和处理全部订单',
        'category': 'commerce',
      });

      expect(tile.highlighted, isFalse);
    });

    test('tryFromJson 对缺失字段返回 SerializationFailure', () {
      final result = KoiWorkspaceTile.tryFromJson(<String, dynamic>{
        'title': '订单中心',
      });

      final failure = result.match(
        (value) => value,
        (_) => throw TestFailure('缺失字段不应反序列化成功'),
      );
      expect(failure, isA<SerializationFailure>());
      expect(failure.displayMessage, '数据格式无效');
    });

    test('tryFromJson 对错误字段类型返回 SerializationFailure', () {
      final result = KoiWorkspaceTile.tryFromJson(<String, dynamic>{
        'title': '订单中心',
        'description': '查看和处理全部订单',
        'category': 'commerce',
        'highlighted': 'yes',
      });

      expect(
        result.match((failure) => failure, (_) => null),
        isA<SerializationFailure>(),
      );
    });
  });
}
