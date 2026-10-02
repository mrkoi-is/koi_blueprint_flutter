import 'dart:async';
import 'dart:ui' show AppExitType, AppExitResponse;

import 'package:flutter/services.dart';
import 'package:platform_lab/features/desktop_window/data/plugin_window_port.dart';
import 'package:platform_lab/features/desktop_window/data/window_geometry_store.dart';
import 'package:platform_lab/features/desktop_window/application/window_host.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'desktop_window_providers.g.dart';

/// Installed capability bootstrap owns this native resource, not a route widget.
abstract final class DesktopWindowRuntime {
  static DesktopWindowHost? host;
  static String? error;
}

Future<void>? _initializing;
Future<void> initializeDesktopWindow() => _initializing ??=
    _initializeDesktopWindow().whenComplete(() => _initializing = null);

Future<void> _initializeDesktopWindow() async {
  if (DesktopWindowRuntime.host?.ready == true) return;
  try {
    await DesktopWindowRuntime.host?.shutdown();
    DesktopWindowRuntime.host = null;
    DesktopWindowRuntime.error = null;
    final host = DesktopWindowHost(
      port: PluginWindowPort(),
      store: await openWindowGeometryStore(),
      requestExit: () async {
        // Existing host WidgetsBindingObserver saves drafts and may cancel exit.
        return await ServicesBinding.instance.exitApplication(
              AppExitType.cancelable,
            ) ==
            AppExitResponse.exit;
      },
    );
    DesktopWindowRuntime.host = host;
    await host.initialize();
  } catch (failure) {
    DesktopWindowRuntime.error = '$failure';
  }
}

@Riverpod(keepAlive: true)
DesktopWindowHost? desktopWindowHost(Ref ref) => DesktopWindowRuntime.host;

Future<bool> prepareDesktopWindow() async {
  final host = DesktopWindowRuntime.host;
  if (host == null || !host.ready) return true;
  await host.saveGeometry();
  return host.error == null;
}

Future<void> disposeDesktopWindow() async {
  final host = DesktopWindowRuntime.host;
  DesktopWindowRuntime.host = null;
  if (host != null) await host.shutdown();
}
