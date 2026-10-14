@TestOn('browser')
library;

import 'package:device_lab/features/devices/data/device_settings_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('real localStorage restores interrupted onboarding and survives owner close', () async {
    final key = 'koi_device_test_${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => web.window.localStorage.removeItem(key));
    final first = WebDeviceSettings(key: key);
    await first.write({
      'onboarding': {'step': 'directory', 'language': 'en'},
      'documents': {'kept': '中文'},
    });
    await first.close();
    await expectLater(first.write({}), throwsStateError);
    final second = WebDeviceSettings(key: key);
    expect(await second.read(), {
      'onboarding': {'step': 'directory', 'language': 'en'},
      'documents': {'kept': '中文'},
    });
    await second.close();
  });
}
