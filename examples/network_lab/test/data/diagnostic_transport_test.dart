import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:network_lab/shared/network/diagnostic_http_transport.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

final class Fixture implements HttpTransport {
  Fixture(this.bytes);
  final List<int> bytes;
  bool listened = false;
  @override
  Future<HttpPayload> open(
    Uri uri, {
    required Cancellation cancellation,
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    Stream<List<int>> body() async* {
      listened = true;
      yield bytes;
    }

    return HttpPayload(
      status: 200,
      headers: {'content-type': 'application/json'},
      body: body(),
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('observes JSON only when consumed and preserves every byte', () async {
    final store = BoundedDiagnosticStore();
    final remove = Diagnostics.register(store.record);
    final bytes = utf8.encode('{"access_token":"sensitive","ok":true}');
    final fixture = Fixture(bytes);
    final transport = DiagnosticHttpTransport(fixture);
    final result = await transport.open(
      Uri.parse('https://host'),
      cancellation: Cancellation(),
    );
    expect(fixture.listened, isFalse);
    expect(store.snapshot.last.network!['state'], 'receiving');
    expect(await result.body.expand((x) => x).toList(), bytes);
    expect(store.snapshot.last.network!['state'], 'complete');
    expect(
      jsonEncode(store.snapshot.last.toJson()),
      isNot(contains('sensitive')),
    );
    await transport.close();
    remove();
    await store.close();
  });
}
