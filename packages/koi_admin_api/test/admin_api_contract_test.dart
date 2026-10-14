import 'package:dio/dio.dart';
import 'package:koi_admin_api/koi_admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('生成 Client 保持 method、path 和运行时 baseUrl', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://runtime.example.com/admin/'));
    String? method;
    String? path;
    Uri? requestUri;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          method = options.method;
          path = options.path;
          requestUri = options.uri;
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              data: {'status': 'ok', 'version': '1.2.3'},
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final client = AdminApiClient(dio, baseUrl: dio.options.baseUrl);

    final result = await client.system.getHealth();

    expect(method, 'GET');
    expect(path, '/health');
    expect(requestUri?.origin, 'https://runtime.example.com');
    expect(requestUri?.path, '/admin/health');
    expect(result.status, AdminServiceStatus.ok);
    expect(result.version, '1.2.3');
  });

  test('运行时 baseUrl 的固定 path prefix 不依赖末尾斜杠', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://runtime.example.com/admin'));
    Uri? requestUri;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestUri = options.uri;
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              data: {'status': 'ok'},
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final client = AdminApiClient(dio, baseUrl: dio.options.baseUrl);

    await client.system.getHealth();

    expect(requestUri?.path, '/admin/health');
  });

  test('服务端新增枚举值落到 unknown fallback', () {
    final result = AdminHealthStatus.fromJson({
      'status': 'future_server_value',
    });

    expect(result.status, AdminServiceStatus.unknown);
  });

  test('契约中的 unknown 与未知 fallback 保持区分', () {
    final result = AdminHealthStatus.fromJson({'status': 'unknown'});

    expect(result.status, AdminServiceStatus.unknownValue);
  });
}
