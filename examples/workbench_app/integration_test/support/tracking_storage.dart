import 'package:workbench_app/features/workspace/data/workspace_storage.dart';
import 'package:workbench_app/features/workspace/domain/workspace_ports.dart';

/// Observes lifetime calls while forwarding every operation to actual storage.
class TrackingStorage implements WorkspaceStorage {
  TrackingStorage(this.actual);
  final WorkspaceStorage actual;
  final leases = <TrackingLease>[];
  @override
  WorkspaceRepository get repository => actual.repository;
  @override
  AssetStore get assetStore => actual.assetStore;
  @override
  String? get warning => actual.warning;
  @override
  Future<AssetPreviewLease> openPreview(String key) async {
    final lease = TrackingLease(await actual.openPreview(key));
    leases.add(lease);
    return lease;
  }

  @override
  Future<void> close() => actual.close();
}

class TrackingLease implements AssetPreviewLease {
  TrackingLease(this.actual);
  final AssetPreviewLease actual;
  int releaseCount = 0;
  @override
  String get uri => actual.uri;
  @override
  Future<void> dispose() async {
    releaseCount++;
    await actual.dispose();
  }
}
