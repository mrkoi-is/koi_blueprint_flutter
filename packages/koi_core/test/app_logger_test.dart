import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  group('AppLogger', () {
    tearDown(() => AppLogger.sink = null);

    test('按级别转发消息、错误与堆栈', () {
      final records = <(AppLogLevel, String)>[];
      Object? capturedError;
      StackTrace? capturedStackTrace;
      AppLogger.sink = (level, message, {error, stackTrace}) {
        records.add((level, message));
        capturedError = error;
        capturedStackTrace = stackTrace;
      };

      final failure = StateError('boom');
      final stackTrace = StackTrace.fromString('stack');
      AppLogger.debug('调试');
      AppLogger.info('信息');
      AppLogger.warning('警告');
      AppLogger.error('错误', error: failure, stackTrace: stackTrace);

      expect(records, <(AppLogLevel, String)>[
        (AppLogLevel.debug, '调试'),
        (AppLogLevel.info, '信息'),
        (AppLogLevel.warning, '警告'),
        (AppLogLevel.error, '错误'),
      ]);
      expect(capturedError, same(failure));
      expect(capturedStackTrace, same(stackTrace));
    });

    test('sink 置空后恢复默认输出且不抛错', () {
      AppLogger.sink = (level, message, {error, stackTrace}) {};
      AppLogger.sink = null;

      expect(() => AppLogger.info('恢复默认输出'), returnsNormally);
    });
  });
}
