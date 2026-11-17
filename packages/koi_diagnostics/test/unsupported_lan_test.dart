import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_diagnostics/src/diagnostic_lan_stub.dart';

void main() {
  test('browser host reports unsupported without pretending to run', () async {
    final store = BoundedDiagnosticStore();
    final lan = DiagnosticLan(() => store);
    expect(lan.supported, isFalse);
    expect(lan.running, isFalse);
    expect(lan.busy, isFalse);
    expect(lan.address, isNull);
    expect(lan.credential, isNull);
    expect(lan.error, isNull);
    expect(await lan.interfaces(), isEmpty);
    await expectLater(lan.start(), throwsA(isA<UnsupportedError>()));
    await lan.stop();
    await lan.close();
    await store.close();
  });
}
