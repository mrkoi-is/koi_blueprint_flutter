import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_diagnostics/koi_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'Talker records safe network snapshots and closes its registration',
    () async {
      final store = BoundedDiagnosticStore();
      final recorder = TalkerDiagnosticRecorder(() => store);
      recorder.record(AppLogLevel.warning, 'warning', source: 'test');
      final headers = {
        'Authorization': 'Bearer sensitive',
        'Accept': 'application/json',
      };
      final trace = Diagnostics.startNetwork(
        'POST',
        Uri.parse('https://host/path?token=secret'),
        headers: headers,
        body: {
          'password': 'secret',
          'nested': {'token': 'secret'},
        },
      )!;
      trace.response(200, {'Set-Cookie': 'private'}, body: {'ok': true});
      trace.finish();
      trace.finish(error: 'duplicate');
      expect(store.snapshot, hasLength(4));
      final raw = jsonEncode(store.snapshot.map((e) => e.toJson()).toList());
      expect(raw, isNot(contains('sensitive')));
      expect(raw, isNot(contains('private')));
      expect(raw, isNot(contains('secret')));
      expect(headers['Authorization'], 'Bearer sensitive');
      expect(store.snapshot.last.network!['state'], 'complete');
      recorder.close();
      expect(
        Diagnostics.startNetwork('GET', Uri.parse('https://host')),
        isNull,
      );
      await store.close();
    },
  );
  test(
    'native LAN authenticates, exports, streams and stops its port',
    () async {
      final store = BoundedDiagnosticStore();
      final lan = DiagnosticLan(() => store);
      final client = HttpClient();
      Future<T> within<T>(String operation, Future<T> future) => future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('LAN test: $operation'),
      );
      Future<String> read(HttpClientResponse response) =>
          within('read finite response', utf8.decodeStream(response));
      Future<HttpClientResponse> get(String path, {bool auth = true}) async {
        final request = await within(
          'connect $path',
          client.getUrl(Uri.parse('${lan.address}$path')),
        );
        if (auth) {
          request.headers.set('Authorization', 'Bearer ${lan.credential}');
        }
        return within('response headers $path', request.close());
      }

      try {
        await within('start listener', lan.start(address: '127.0.0.1'));
        expect(lan.running, isTrue);
        final firstCredential = lan.credential;
        final root = await get('/', auth: false);
        expect(await read(root), contains('EventSource'));
        final denied = await get('/records', auth: false);
        expect(denied.statusCode, 401);
        await within('drain denied response', denied.drain<void>());
        store.record(AppLogLevel.info, '<script>text</script>');
        final page = jsonDecode(await read(await get('/records'))) as Map;
        expect(
          (page['items'] as List).single['message'],
          '<script>text</script>',
        );
        final export = await read(await get('/export'));
        expect(export, contains('message'));
        final stream = await get('/events');
        final lines = StreamIterator(
          stream.transform(utf8.decoder).transform(const LineSplitter()),
        );
        expect(await within('initial SSE frame', lines.moveNext()), isTrue);
        expect(lines.current, startsWith('data:'));
        expect(await within('SSE separator', lines.moveNext()), isTrue);
        store.record(AppLogLevel.info, 'live update');
        expect(await within('live SSE revision', lines.moveNext()), isTrue);
        expect(lines.current, 'data: ${store.revision}');
        final oldAddress = lan.address!;
        await lan.stop().timeout(const Duration(seconds: 5));
        await lines.cancel().timeout(const Duration(seconds: 5));
        expect(lan.running, isFalse);
        expect(lan.credential, isNull);
        await expectLater(() async {
          final probe = HttpClient();
          try {
            final request = await probe.getUrl(
              Uri.parse('$oldAddress/records'),
            );
            await request.close();
          } finally {
            probe.close(force: true);
          }
        }(), throwsA(isA<SocketException>()));
        await within('restart listener', lan.start(address: '127.0.0.1'));
        expect(lan.credential, isNot(firstCredential));
        await within('stop restarted listener', lan.stop());
        // Fail binding locally, without platform-specific DNS/NetBIOS retries.
        await within('reject nonlocal bind', lan.start(address: '192.0.2.1'));
        expect(lan.error, isNotNull);
        expect(lan.running, isFalse);
      } finally {
        client.close(force: true);
        await within('close listener', lan.close());
        await within('close store', store.close());
      }
    },
  );
  test('shared vocabulary covers all supported locales', () {
    for (final language in ['en', 'zh', 'zh_Hant']) {
      final s = DiagnosticStrings(language);
      expect(
        [
          s.logs,
          s.network,
          s.lan,
          s.start,
          s.stop,
          s.credential,
          s.unsupported,
          s.failed,
          s.search,
          s.export,
          s.loadMore,
          s.source,
          s.allLevels,
          s.empty,
        ].every((v) => v.isNotEmpty),
        isTrue,
      );
    }
  });
}
