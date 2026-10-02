@TestOn('vm')
library;

import 'dart:io';

import 'package:device_lab/features/devices/data/device_settings_native.dart';
import 'package:device_lab/features/devices/data/incoming_file_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native settings persist serial writes, recover backup and reject post-close access', () async {
    final directory = await Directory.systemTemp.createTemp(
      'koi_device_settings_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/nested/settings.json');
    final store = NativeDeviceSettings(file);
    expect(await store.read(), isEmpty);
    await store.write({'language': 'en', 'document': '中文'});
    await store.write({'language': 'zh'});
    await store.close();
    expect(() => store.read(), throwsStateError);
    final reopened = NativeDeviceSettings(file);
    expect((await reopened.read())['language'], 'zh');
    await file.writeAsString('corrupted');
    expect((await reopened.read())['document'], '中文');
    await reopened.close();
  });
  test('file intent imports real UTF-8 text and bounds size', () async {
    final directory = await Directory.systemTemp.createTemp('koi_device_file_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/资料.txt');
    await file.writeAsString('中文内容');
    expect((await readIncomingFile(file.path)).text, '中文内容');
    await file.writeAsBytes(List.filled(256 * 1024 + 1, 65));
    await expectLater(readIncomingFile(file.path), throwsFormatException);
  });
}
