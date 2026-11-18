import 'dart:io';

import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

import 'ai_sandbox_types.dart';

Future<AiSandbox> createSandbox(String id) async {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}koi_ai_$id';
  final kind = await FileSystemEntity.type(path, followLinks: false);
  if (kind != FileSystemEntityType.notFound &&
      kind != FileSystemEntityType.directory) {
    throw StateError('AI fixture path must be a directory, not a link or file');
  }
  await Directory(path).create();
  return _NativeSandbox(id, path);
}

class _NativeSandbox implements AiSandbox {
  _NativeSandbox(this.id, this.location);
  @override
  final String id;
  @override
  final String location;
  @override
  Future<WorkspaceStorage> open() =>
      openWorkspaceStorage(nativeDirectory: location);
}
