import 'package:dio/dio.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

HttpTransport createHttpTransport() => DioHttpTransport();

final class DioHttpTransport implements HttpTransport {
  DioHttpTransport()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
  final Dio _dio;
  bool _closed = false;
  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    if (_closed) throw StateError('HTTP transport closed');
    cancellation.check();
    final token = CancelToken();
    final detach = cancellation.onCancel(
      () => token.cancel('Cancelled by owner'),
    );
    try {
      final response = await _dio.request<ResponseBody>(
        uri.toString(),
        cancelToken: token,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );
      final body = response.data!;
      Stream<List<int>> stream() async* {
        try {
          await for (final bytes in body.stream) {
            cancellation.check();
            yield bytes;
          }
          cancellation.check();
        } on DioException catch (error) {
          if (cancellation.isCancelled || CancelToken.isCancel(error)) {
            throw const RequestCancelled();
          }
          rethrow;
        } finally {
          detach();
        }
      }

      return HttpPayload(
        status: response.statusCode!,
        headers: response.headers.map.map(
          (key, value) => MapEntry(key, value.join(',')),
        ),
        body: stream(),
      );
    } on DioException catch (error) {
      detach();
      if (cancellation.isCancelled || CancelToken.isCancel(error)) {
        throw const RequestCancelled();
      }
      rethrow;
    } catch (_) {
      detach();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _dio.close(force: true);
  }
}
