@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:network_lab/features/images/data/local_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native local reader reads selected path, bounds bytes and rejects missing or closed reads', () async {
    final directory = await Directory.systemTemp.createTemp('network-images-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/image')..writeAsBytesSync([1, 2, 3]);
    final reader = createLocalImageReader();
    expect(await reader.read(file.path, maxBytes: 3), [1, 2, 3]);
    await expectLater(reader.read(file.path, maxBytes: 2), throwsStateError);
    await expectLater(
      reader.read('${directory.path}/absent', maxBytes: 10),
      throwsA(isA<FileSystemException>()),
    );
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openFile');
      return [file.path];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await reader.pick(maxBytes: 10), file.path);
    await expectLater(reader.pick(maxBytes: 2), throwsStateError);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await reader.pick(maxBytes: 10), null);
    reader.close();
    await expectLater(reader.read(file.path, maxBytes: 10), throwsStateError);
  });
}
