import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/images/data/local_reader_stub.dart';

void main() {
  test(
    'unsupported platform explicitly rejects local image reader creation',
    () {
      expect(createLocalImageReader, throwsUnsupportedError);
    },
  );
}
