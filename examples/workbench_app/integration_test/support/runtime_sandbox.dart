import 'runtime_sandbox_stub.dart'
    if (dart.library.io) 'runtime_sandbox_native.dart'
    if (dart.library.js_interop) 'runtime_sandbox_web.dart'
    as platform;
import 'runtime_sandbox_types.dart';

export 'runtime_sandbox_types.dart';

Future<RuntimeSandbox> createRuntimeSandbox() => platform.createSandbox();
