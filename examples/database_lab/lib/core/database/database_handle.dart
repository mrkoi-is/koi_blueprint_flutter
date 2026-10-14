import 'package:database_lab/features/library/domain/library_repository.dart';
import 'package:drift/drift.dart';

final class DatabaseHandle {
  const DatabaseHandle(this.executor, this.availability);
  final QueryExecutor executor;
  final DatabaseAvailability availability;
}
