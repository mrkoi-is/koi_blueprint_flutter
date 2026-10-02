@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

import '../support/fixture_transport.dart';

void main() {
  // Reproduce a host test configuration that initializes its binding first.
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native transport streams actual local bytes and aborts a pending request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>();
      final release = Completer<void>();
      server.listen((request) async {
        if (request.uri.path == '/pending') {
          started.complete();
          await release.future;
        }
        request.response.headers.set('ETag', '"test"');
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      final hostOverrides = HttpOverrides.current;
      final transport = createFixtureHttpTransport();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await transport.close();
        await server.close(force: true);
      });
      final base = Uri.parse('http://127.0.0.1:${server.port}/');
      final response = await transport.open(base, cancellation: Cancellation());
      expect(response.status, 200);
      expect(response.headers['etag'], '"test"');
      expect(await response.body.expand((bytes) => bytes).toList(), [1, 2, 3]);
      expect(identical(HttpOverrides.current, hostOverrides), true);
      final hostClient = HttpClient();
      final hostRequest = await hostClient.getUrl(base);
      expect((await hostRequest.close()).statusCode, 400);
      hostClient.close(force: true);
      final cancel = Cancellation();
      final pending = transport.open(
        base.resolve('pending'),
        cancellation: cancel,
      );
      final assertion = expectLater(pending, throwsA(isA<RequestCancelled>()));
      await started.future;
      cancel.cancel();
      await assertion;
      release.complete();
      await transport.close();
      await expectLater(
        transport.open(base, cancellation: Cancellation()),
        throwsStateError,
      );
    },
  );
}
