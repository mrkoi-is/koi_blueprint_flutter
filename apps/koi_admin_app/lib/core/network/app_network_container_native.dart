import 'package:koi_admin_api/koi_admin_api.dart';
import 'package:koi_admin_app/core/network/app_network_container.dart';
import 'package:koi_admin_app/features/system/data/system_status_gateway_impl.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap_native.dart';

AppNetworkContainer createAppNetworkContainer(KoiApiRuntime runtime) {
  final client = buildKoiApiClient(
    runtime,
    'main',
    (dio) => AdminApiClient(dio, baseUrl: dio.options.baseUrl),
  );
  return AppNetworkContainer(
    systemStatusGateway: SystemStatusGatewayImpl(client),
  );
}
