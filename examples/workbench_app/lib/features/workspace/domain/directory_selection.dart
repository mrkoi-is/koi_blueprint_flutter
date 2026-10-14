import 'package:workbench_app/features/workspace/domain/directory_index.dart';

final class DirectorySelection {
  const DirectorySelection({
    required this.label,
    required this.identity,
    required this.source,
  });
  final String label;

  /// Only the controller compares this token; the UI never presents a path.
  final String identity;
  final DirectoryIndexSource source;
}

abstract interface class DirectoryIndexPicker {
  Future<DirectorySelection?> pick();
}
