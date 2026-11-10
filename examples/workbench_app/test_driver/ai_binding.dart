import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_test/flutter_test.dart'
    show TestDefaultBinaryMessengerBinding;
import 'package:workbench_app/core/window/workbench_exit_binding.dart';

import 'ai_driver_stub.dart' if (dart.library.js_interop) 'ai_driver_web.dart';

/// The standard driver initializer owns a private incompatible WidgetsBinding.
/// Register its debug service on a binding that retains Workbench exit handling.
class AiWorkbenchBinding extends WidgetsFlutterBinding
    with TestDefaultBinaryMessengerBinding, WorkbenchExitBinding {
  @override
  bool debugCheckZone(String entryPoint) => true;

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();
    final extension = FlutterDriverExtension(null, false, true);
    registerServiceExtension(name: 'driver', callback: extension.call);
    registerAiWebDriver(extension.call);
  }
}
