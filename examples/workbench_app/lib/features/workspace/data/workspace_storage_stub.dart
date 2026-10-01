import 'package:workbench_app/features/workspace/data/workspace_storage_types.dart';

Future<WorkspaceStorage> openStorage({
  String? nativeDirectory,
  String webDatabaseName = 'koi_workbench',
}) async => throw UnsupportedError('当前平台没有工作区持久化实现');
