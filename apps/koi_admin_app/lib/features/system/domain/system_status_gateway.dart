import 'package:koi_core/koi_core.dart';

enum SystemServiceState { healthy, degraded, unknown }

final class SystemHealth {
  const SystemHealth({required this.state, this.version});

  final SystemServiceState state;
  final String? version;
}

abstract interface class SystemStatusGateway {
  FutureResult<SystemHealth> readHealth();
}
