import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/core/window/workbench_exit_binding.dart';

// Existing presentation expectations are Chinese. Locale-focused tests override
// this fixture explicitly; the product continues to follow the OS by default.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = _WorkbenchTestBinding();
  setUp(
    () => binding.platformDispatcher.localesTestValue = [const Locale('zh')],
  );
  tearDown(binding.platformDispatcher.clearLocalesTestValue);
  await testMain();
}

class _WorkbenchTestBinding extends AutomatedTestWidgetsFlutterBinding
    with WorkbenchExitBinding {}
