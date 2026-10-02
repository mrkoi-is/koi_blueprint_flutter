import 'package:device_lab/features/devices/data/incoming_file_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'external file URI is rejected without fabricating a browser document',
    () async {
      await expectLater(
        readIncomingFile('/private/selected.txt'),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
