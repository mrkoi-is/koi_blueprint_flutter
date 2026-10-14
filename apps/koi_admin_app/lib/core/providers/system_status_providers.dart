import 'package:koi_admin_app/features/system/domain/system_status_gateway.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_status_providers.g.dart';

@Riverpod(keepAlive: true)
SystemStatusGateway systemStatusGateway(Ref ref) {
  throw UnimplementedError('由 bootstrap 注入 SystemStatusGateway');
}
