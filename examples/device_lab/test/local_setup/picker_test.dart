@TestOn('vm')
library;

import 'dart:io';

import 'package:device_lab/features/devices/data/pick_directory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native selector preserves cancel, selection scope and actual Unicode bytes', () async {
    final root = await Directory.systemTemp.createTemp('device-picker-');
    addTearDown(() => root.delete(recursive: true));
    final file = await File('${root.path}/中文.md')
        .writeAsString('正文 👩🏽‍💻\nsecond');
    String? picked;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDirectoryPath') return root.path;
      expect(call.method, 'openFile');
      final options = call.arguments as Map;
      expect(options['initialDirectory'], root.path);
      expect(options['multiple'], false);
      return picked == null ? null : [picked];
    });
    expect(await pickSetupDirectory(), root.path);
    expect(await pickIncomingDocument(root.path), isNull);
    picked = file.path;
    final imported = await pickIncomingDocument(root.path);
    expect(imported!.name, '中文.md');
    expect(imported.text, '正文 👩🏽‍💻\nsecond');
    await file.writeAsBytes([0xff, 0xfe]);
    await expectLater(pickIncomingDocument(root.path), throwsFormatException);
    await file.writeAsBytes(List<int>.filled(256 * 1024 + 1, 65));
    await expectLater(pickIncomingDocument(root.path), throwsFormatException);
  });
}
