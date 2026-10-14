import 'package:dio/dio.dart';
import 'package:koi_admin_api/koi_admin_api.dart';
import 'package:koi_admin_app/features/system/domain/system_status_gateway.dart';
import 'package:koi_core/koi_core.dart';

final class SystemStatusGatewayImpl implements SystemStatusGateway {
  const SystemStatusGatewayImpl(this._api);

  final AdminApiClient _api;

  @override
  FutureResult<SystemHealth> readHealth() async {
    try {
      final dto = await _api.system.getHealth();
      return success(
        SystemHealth(
          state: switch (dto.status) {
            AdminServiceStatus.ok => SystemServiceState.healthy,
            AdminServiceStatus.degraded => SystemServiceState.degraded,
            AdminServiceStatus.unknownValue ||
            AdminServiceStatus.unknown => SystemServiceState.unknown,
          },
          version: dto.version,
        ),
      );
    } on DioException catch (error) {
      return failure(
        error.response?.statusCode == 401
            ? const AppFailure.unauthorized()
            : const AppFailure.network(message: '无法读取服务状态'),
      );
    } on Object {
      // Keep generated DTO/transport errors out of the domain contract.
      return failure(const AppFailure.serialization());
    }
  }
}
