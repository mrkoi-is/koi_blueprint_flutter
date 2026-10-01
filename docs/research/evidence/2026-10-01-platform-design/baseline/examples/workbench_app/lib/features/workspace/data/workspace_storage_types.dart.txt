import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Platform-specific source kept outside the pure domain contract.
abstract interface class AssetPreviewLease {
  String get uri;
  Future<void> dispose();
}

abstract interface class WorkspaceStorage {
  WorkspaceRepository get repository;
  AssetStore get assetStore;
  String? get warning;
  Future<AssetPreviewLease> openPreview(String key);
  Future<void> close();
}
