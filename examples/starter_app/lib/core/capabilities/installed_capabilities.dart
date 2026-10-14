// Managed by blueprint capability add. User entries belong in app_capabilities.dart.
import 'package:starter_app/core/capabilities/app_capability.dart';
import 'package:starter_app/core/capabilities/capability_lifecycle.dart';

const installedCapabilities = <AppCapabilityPage>[];

Future<void> initializeInstalledCapabilities() async {}

Future<bool> prepareInstalledCapabilities() async {
  return CapabilityLifecycle.instance.prepare();
}

Future<void> disposeInstalledCapabilities() =>
    CapabilityLifecycle.instance.close();
