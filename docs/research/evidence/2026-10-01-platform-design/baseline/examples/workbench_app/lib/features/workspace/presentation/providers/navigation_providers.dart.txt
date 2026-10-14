import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workbench_app/core/router/workbench_navigation_history.dart';

part 'navigation_providers.g.dart';

/// Borrowed from bootstrap, which awaits history cleanup before closing IO.
@Riverpod(keepAlive: true)
WorkbenchNavigationHistory navigationHistory(Ref ref) =>
    throw UnimplementedError('Bootstrap must inject navigation history');
