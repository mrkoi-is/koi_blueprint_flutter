import 'package:workbench_app/core/capabilities/app_capability.dart';
import 'package:workbench_app/core/capabilities/installed_capabilities.dart';
export 'package:workbench_app/core/capabilities/app_capability.dart';

/// App-owned entries. The capability installer only changes installed_capabilities.dart.
const userCapabilities = <AppCapabilityPage>[];

List<AppCapabilityPage> get appCapabilities {
  final result = [...installedCapabilities, ...userCapabilities];
  final ids = <String>{};
  for (final item in result) {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(item.id) || !ids.add(item.id)) {
      throw StateError('Invalid or duplicate capability id: ${item.id}');
    }
  }
  return List.unmodifiable(result);
}
