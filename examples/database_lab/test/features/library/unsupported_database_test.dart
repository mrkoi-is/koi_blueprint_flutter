import 'package:database_lab/core/database/open_database_unsupported.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unsupported storage rejects opening instead of reporting persistence',
    () {
      final unavailable = throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'reason',
          contains('unavailable'),
        ),
      );
      expect(openDatabase, unavailable);
      expect(() => openDatabase(name: 'requested-library'), unavailable);
    },
  );
}
