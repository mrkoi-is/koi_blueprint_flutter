import 'ai_persistence_sandbox_stub.dart'
    if (dart.library.io) 'ai_persistence_sandbox_native.dart'
    if (dart.library.js_interop) 'ai_persistence_sandbox_web.dart'
    as platform;
import 'ai_persistence_sandbox_types.dart';

export 'ai_persistence_sandbox_types.dart';

Future<RuntimeSandbox> createRuntimeSandbox() => platform.createSandbox();
