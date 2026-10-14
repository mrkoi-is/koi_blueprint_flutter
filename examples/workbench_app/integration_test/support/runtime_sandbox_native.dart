import 'dart:io';

import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

import 'runtime_sandbox_types.dart';

Future<RuntimeSandbox> createSandbox() async => _NativeSandbox(
  await Directory.systemTemp.createTemp('koi_runtime_fixture_'),
);

class _NativeSandbox implements RuntimeSandbox {
  const _NativeSandbox(this.directory);
  final Directory directory;
  @override
  String get description => 'Native isolated temporary directory';
  @override
  Future<WorkspaceStorage> open() =>
      openWorkspaceStorage(nativeDirectory: directory.path);
  @override
  Future<void> verifyReleasedUri(String uri) async {
    // Native file leases do not invalidate files: content must survive playback.
    if (!await File.fromUri(Uri.parse(uri)).exists()) {
      throw StateError(
        'Playback release unexpectedly removed persisted content',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
