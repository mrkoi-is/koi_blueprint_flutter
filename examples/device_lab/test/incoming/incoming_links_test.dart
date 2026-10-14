@TestOn('vm')
library;

import 'package:device_lab/features/devices/data/incoming_links.dart';
import 'package:device_lab/features/devices/data/incoming_file_native.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('inbox buffers before page ready, validates navigation and can be recreated after failed bootstrap', () async {
    final source = FakeLinks()..initialUri = Uri.parse('koi://tasks');
    var navigations = 0;
    final inbox = IncomingLinkInbox(
      source: source,
      onIncoming: () => navigations++,
    );
    inbox.start();
    await Future<void>.delayed(Duration.zero);
    final received = <Uri>[];
    final subscription = inbox.links.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    expect(received.single.toString(), 'koi://tasks');
    source.events.add(Uri.parse('koi://document?id=welcome'));
    await Future<void>.delayed(Duration.zero);
    expect(received.length, 2);
    expect(navigations, 2);
    await subscription.cancel();
    await inbox.close();
    await source.events.close();
    final first = IncomingLinkInbox.instance;
    await first.close();
    expect(IncomingLinkInbox.instance, isNot(same(first)));
    await IncomingLinkInbox.instance.close();
    final retrySource = FakeLinks()..initialUri = Uri.parse('koi://tasks');
    final retry = IncomingLinkInbox(source: retrySource, onIncoming: () {});
    retry.start();
    expect((await retry.links.first).host, 'tasks');
    await retry.close();
    await retrySource.events.close();
  });
  test('web initial URI normalizes only explicit commands', () {
    expect(normalizeIncomingUri(Uri.parse('http://localhost:8080/')), isNull);
    expect(
      normalizeIncomingUri(
        Uri.parse('http://localhost/?koi-intent=koi%3A%2F%2Ftasks'),
      ),
      Uri.parse('koi://tasks'),
    );
    expect(
      normalizeIncomingUri(Uri.parse('http://localhost/#/document?id=welcome'))
          ?.path,
      '/document',
    );
    expect(
      IncomingIntent.fromUri(Uri.parse('content://provider/document/1')).action,
      IncomingAction.importFile,
    );
  });
  test('Android content channel returns actual UTF-8 bytes, bounds content and propagates grant failure', () async {
    const channel = MethodChannel('koi_blueprint/incoming_files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readContent');
      expect((call.arguments as Map)['uri'], 'content://provider/document/1');
      return {
        'name': 'shared.txt',
        'bytes': Uint8List.fromList([104, 105]),
      };
    });
    final document = await readIncomingFile('content://provider/document/1');
    expect(document.name, 'shared.txt');
    expect(document.text, 'hi');
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'content_read_failed',
        message: 'grant expired',
      ),
    );
    await expectLater(
      readIncomingFile('content://provider/document/1'),
      throwsA(isA<PlatformException>()),
    );
  });
}
