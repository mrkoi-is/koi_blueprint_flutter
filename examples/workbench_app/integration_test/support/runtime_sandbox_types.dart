import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

abstract interface class RuntimeSandbox {
  String get description;
  Future<WorkspaceStorage> open();
  Future<void> verifyReleasedUri(String uri);
  Future<void> dispose();
}
