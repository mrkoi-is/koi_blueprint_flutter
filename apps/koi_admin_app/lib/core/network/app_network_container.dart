import 'package:koi_admin_app/core/network/app_network_container_stub.dart'
    if (dart.library.io) 'package:koi_admin_app/core/network/app_network_container_native.dart'
    as backend;
import 'package:koi_admin_app/features/system/domain/system_status_gateway.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';

/// Composition Root owns the runtime; this container only exposes domain ports.
final class AppNetworkContainer {
  const AppNetworkContainer({required this.systemStatusGateway});

  factory AppNetworkContainer.fromRuntime(KoiApiRuntime runtime) =>
      backend.createAppNetworkContainer(runtime);

  final SystemStatusGateway systemStatusGateway;
}
