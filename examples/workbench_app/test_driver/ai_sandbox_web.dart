import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

import 'ai_sandbox_types.dart';

Future<AiSandbox> createSandbox(String id) async => _WebSandbox(id);

class _WebSandbox implements AiSandbox {
  _WebSandbox(this.id);
  @override
  final String id;
  @override
  String get location => 'koi_ai_$id';
  @override
  Future<WorkspaceStorage> open() =>
      openWorkspaceStorage(webDatabaseName: location);
}
