@TestOn('browser')
library;

import 'dart:convert';

import '../presentation/network_capability_test.dart' as pages;
import '../application/transfer_engine_test.dart' as transfers;
import '../data/cache_repository_test.dart' as cache;

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/data/http_transport.dart';
import 'package:network_lab/features/network/data/transfer_store.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

void main() {
  // Chrome does not always forward Flutter's console dump to the CLI reporter.
  final report = reportTestException;
  reportTestException = (details, description) => report(
    details,
    '$description\n${details.exceptionAsString()}\n${details.stack}',
  );
  pages.main();
  transfers.main();
  cache.main();
  test('Fetch reads actual browser stream and cancellation before request is honored', () async {
    final transport = createHttpTransport();
    addTearDown(transport.close);
    final response = await transport.open(
      Uri.dataFromString(
        '真实 browser bytes',
        mimeType: 'text/plain',
        encoding: utf8,
      ),
      cancellation: Cancellation(),
    );
    expect(response.status, 200);
    expect(
      utf8.decode(await response.body.expand((chunk) => chunk).toList()),
      '真实 browser bytes',
    );
    await expectLater(
      transport.open(
        Uri.parse('data:text/plain,no'),
        cancellation: Cancellation()..cancel(),
      ),
      throwsA(isA<RequestCancelled>()),
    );
    await transport.close();
    await expectLater(
      transport.open(
        Uri.parse('data:text/plain,no'),
        cancellation: Cancellation(),
      ),
      throwsStateError,
    );
  });
  test('IndexedDB persists chunks atomically and cancellation keeps committed bytes', () async {
    final name = 'network-browser-${DateTime.now().microsecondsSinceEpoch}';
    var store = await openTransferStore(databaseName: name);
    addTearDown(() => store.close());
    const metadata = TransferMetadata(
      source: 'http://fixture/file',
      etag: '"v1"',
      total: 4,
    );
    await expectLater(openTransferStore(databaseName: name), throwsStateError);
    expect(await store.metadata('x'), isNull);
    await store.begin('x', metadata);
    await store.append('x', [1, 2]);
    await store.close();
    store = await openTransferStore(databaseName: name);
    expect(await store.length('x'), 2);
    expect((await store.metadata('x'))!.matches(metadata), true);
    await store.append('x', [3, 4]);
    await store.commit('x', 'digest');
    expect(await store.read('x').expand((v) => v).toList(), [1, 2, 3, 4]);
    await store.begin('x', metadata);
    await store.append('x', [9]);
    await store.discard('x');
    expect(await store.read('x').expand((v) => v).toList(), [1, 2, 3, 4]);
    await store.begin('x', metadata);
    await store.append('x', [8]);
    await store.commit('x', 'replacement');
    expect(await store.read('x').expand((v) => v).toList(), [8]);
    await expectLater(store.append('missing', [1]), throwsStateError);
    await expectLater(store.begin('../bad', metadata), throwsArgumentError);
  });
}
