import 'package:workbench_app/features/workspace/data/workspace_storage_stub.dart'
    if (dart.library.io) 'package:workbench_app/features/workspace/data/workspace_storage_native.dart'
    if (dart.library.js_interop) 'package:workbench_app/features/workspace/data/workspace_storage_web.dart'
    as platform;
import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';

export 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';

Future<WorkspaceStorage> openWorkspaceStorage({
  String? nativeDirectory,
  String webDatabaseName = 'koi_workbench',
}) => platform.openStorage(
  nativeDirectory: nativeDirectory,
  webDatabaseName: webDatabaseName,
);
