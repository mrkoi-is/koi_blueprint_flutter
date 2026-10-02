@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/images/data/local_reader.dart';

import '../images/image_repository_test.dart' as shared;
import '../images/images_page_test.dart' as pages;

void main() {
  // Chrome does not always forward Flutter's console dump to the CLI reporter.
  final report = reportTestException;
  reportTestException = (details, description) => report(
    details,
    '$description\n${details.exceptionAsString()}\n${details.stack}',
  );
  shared.main();
  pages.main();
  test('browser local reader rejects invented paths and closes without file access', () async {
    final reader = createLocalImageReader();
    await expectLater(
      reader.read('/tmp/not-a-browser-file', maxBytes: 100),
      throwsStateError,
    );
    reader.close();
    await expectLater(reader.pick(maxBytes: 100), throwsStateError);
  });
}
