import 'package:flutter_test/flutter_test.dart';
import 'package:platform_lab/features/desktop_window/data/window_geometry_store_stub.dart'
    as unsupported;

void main() {
  test(
    'unsupported geometry storage fails explicitly instead of losing writes',
    () async {
      await expectLater(
        unsupported.open(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'reason',
            isNotEmpty,
          ),
        ),
      );
    },
  );
}
