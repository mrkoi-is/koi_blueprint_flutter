import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/capabilities/installed_capabilities.dart';
import 'package:workbench_app/core/diagnostics/app_diagnostics.dart';
import 'package:workbench_app/main.dart' show WorkbenchLauncher;

import 'ai_binding.dart';
import 'ai_sandbox.dart';

/// Debug-only entrypoint. The normal application never installs this extension.
Future<void> main() async {
  AiWorkbenchBinding();
  AppDiagnostics.instance.install();
  final sandbox = await createAiSandbox();
  debugPrint('KOI_AI_SANDBOX id=${sandbox.id} location=${sandbox.location}');
  await initializeInstalledCapabilities();
  MediaKit.ensureInitialized();
  runApp(
    ProviderScope(
      child: WorkbenchLauncher(
        createBootstrap: () => WorkbenchBootstrap.create(
          openStorage: sandbox.open,
          initialLocation: '/text',
        ),
      ),
    ),
  );
}
