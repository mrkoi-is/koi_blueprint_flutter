import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

void main() {
  test('out-of-order recorder disposal never restores a retired owner', () {
    final events = <String>[];
    void first(
      AppLogLevel level,
      String message, {
      String source = 'app',
      Object? error,
      StackTrace? stackTrace,
      Map<String, Object?>? network,
    }) => events.add('first');
    void second(
      AppLogLevel level,
      String message, {
      String source = 'app',
      Object? error,
      StackTrace? stackTrace,
      Map<String, Object?>? network,
    }) => events.add('second');
    final removeFirst = Diagnostics.register(first);
    final removeSecond = Diagnostics.register(second);
    removeFirst();
    Diagnostics.startNetwork('GET', Uri.parse('https://host'))!.finish();
    expect(events, ['second', 'second']);
    removeSecond();
    expect(Diagnostics.startNetwork('GET', Uri.parse('https://host')), isNull);
  });
  test(
    'boot migration preserves more than 1000 records and structured fields',
    () async {
      final old = BoundedDiagnosticStore();
      for (var i = 0; i < 1200; i++) {
        old.record(AppLogLevel.info, 'boot $i', network: {'id': '$i'});
      }
      final next = BoundedDiagnosticStore()..importEvents(old.snapshot);
      expect(next.snapshot.length, 1200);
      expect(next.snapshot.first.time, old.snapshot.first.time);
      expect(next.snapshot.last.network, {'id': '1199'});
      final restored = DiagnosticEvent.fromJson(next.snapshot.last.toJson());
      expect(restored.network, {'id': '1199'});
      expect(next.query(const DiagnosticQuery(kind: 'log')).items, isEmpty);
      expect(
        next
            .query(const DiagnosticQuery(kind: 'network', text: '1199'))
            .items
            .length,
        1,
      );
      await old.close();
      await next.close();
    },
  );
  test('redacts nested JSON, URL credentials, oversized bodies and cycles', () {
    expect(
      diagnosticUrl(Uri.parse('https://name:pass@host/?access_token=foo&a=1')),
      isNot(contains('foo')),
    );
    expect(
      diagnosticSnapshot('{"password":"hidden","nested":{"token":"hidden"}}')
          .toString(),
      isNot(contains('hidden')),
    );
    expect(
      utf8.encode(diagnosticSnapshot('x' * 70000).toString()).length,
      lessThan(66000),
    );
    final cycle = <String, Object?>{};
    cycle['self'] = cycle;
    expect(diagnosticSnapshot(cycle).toString(), contains('depth limit'));
  });
}
