import 'dart:async';

import 'package:platform_lab/features/desktop_window/presentation/providers/desktop_window_providers.dart';
import 'package:platform_lab/features/tray/data/tray_port.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tray_providers.g.dart';

abstract final class TrayRuntime {
  static TrayPort? port;
  static String? error;
}

Future<void> initializeTray() async {
  await initializeDesktopWindow();
  final host = DesktopWindowRuntime.host;
  if (host == null || !host.ready || TrayRuntime.port != null) return;
  final port = createTrayPort();
  try {
    final available = await port.open(
      show: () => unawaited(host.show()),
      quit: () => unawaited(host.quit()),
    );
    if (!available) {
      await port.close();
      TrayRuntime.error =
          'No system tray is available. Closing still exits normally.';
      return;
    }
    TrayRuntime.port = port;
    host.configureTray(available: true, closeToTray: false);
  } catch (error) {
    await port.close();
    TrayRuntime.error = '$error';
  }
}

@Riverpod(keepAlive: true)
TrayPort? trayPort(Ref ref) => TrayRuntime.port;

Future<bool> prepareTray() async => true;
Future<void> disposeTray() async {
  final port = TrayRuntime.port;
  TrayRuntime.port = null;
  DesktopWindowRuntime.host?.configureTray(
    available: false,
    closeToTray: false,
  );
  await port?.close();
}
