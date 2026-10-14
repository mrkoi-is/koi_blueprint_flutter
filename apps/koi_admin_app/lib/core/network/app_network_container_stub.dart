import 'package:koi_admin_app/core/network/app_network_container.dart';
import 'package:koi_admin_app/features/system/domain/system_status_gateway.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_core/koi_core.dart';

AppNetworkContainer createAppNetworkContainer(KoiApiRuntime runtime) =>
    const AppNetworkContainer(systemStatusGateway: _UnavailableSystemGateway());

final class _UnavailableSystemGateway implements SystemStatusGateway {
  const _UnavailableSystemGateway();

  @override
  FutureResult<SystemHealth> readHealth() async =>
      failure(const AppFailure.network(message: '当前平台尚未接入服务状态 API'));
}
