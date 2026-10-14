import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/directory_index_picker_stub.dart'
    as unsupported;

void main() {
  test('unsupported picker reports an error instead of a cancelled selection', () async {
    // Native and browser conditional imports hide this fallback on test hosts.
    // Exercise the actual fallback contract directly, including a second call.
    final picker = unsupported.createDirectoryIndexPicker();
    final unavailable = throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'reason',
        isNotEmpty,
      ),
    );

    await expectLater(picker.pick(), unavailable);
    await expectLater(picker.pick(), unavailable);
  });
}
