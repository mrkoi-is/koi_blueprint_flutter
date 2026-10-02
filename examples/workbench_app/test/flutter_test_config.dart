import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Existing presentation expectations are Chinese. Locale-focused tests override
// this fixture explicitly; the product continues to follow the OS by default.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.platformDispatcher.localesTestValue = [const Locale('zh')],
  );
  tearDown(binding.platformDispatcher.clearLocalesTestValue);
  await testMain();
}
