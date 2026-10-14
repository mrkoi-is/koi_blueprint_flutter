import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

/// Completes the framework's observer dispatch before irreversible cleanup.
mixin WorkbenchExitBinding on WidgetsBinding {
  Future<AppExitResponse> Function()? _closeWorkbench;
  Future<AppExitResponse>? _pendingExit;

  VoidCallback attachWorkbenchExit(Future<AppExitResponse> Function() close) {
    _closeWorkbench = close;
    return () {
      if (identical(_closeWorkbench, close)) _closeWorkbench = null;
    };
  }

  @override
  Future<AppExitResponse> handleRequestAppExit() =>
      _pendingExit ??= _handleWorkbenchExit();

  Future<AppExitResponse> _handleWorkbenchExit() async {
    try {
      final response = await super.handleRequestAppExit();
      if (response == AppExitResponse.cancel) return response;
      // An asynchronous observer can unmount or replace the app while awaited.
      return await _closeWorkbench?.call() ?? AppExitResponse.exit;
    } finally {
      _pendingExit = null;
    }
  }
}

class WorkbenchWidgetsFlutterBinding extends WidgetsFlutterBinding
    with WorkbenchExitBinding {}
