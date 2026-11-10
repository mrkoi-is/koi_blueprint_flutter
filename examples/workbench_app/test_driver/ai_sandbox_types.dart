import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

abstract interface class AiSandbox {
  String get id;
  String get location;
  Future<WorkspaceStorage> open();
}
