import 'package:platform_lab/features/system_media/data/system_transport.dart';
import 'package:platform_lab/features/system_media/domain/system_transport.dart';

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:platform_lab/features/system_media/application/media_engine_owner.dart';
import 'package:platform_lab/features/system_media/data/media_kit_engine.dart';
import 'package:platform_lab/features/system_media/data/audioplayers_engine.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'system_media_providers.g.dart';

abstract final class SystemMediaRuntime {
  static MediaSessionController? controller;
  static MediaEngineOwner? engines;
  static Future<void>? initializing;
  static String? error;
  static String? transportError;
  static SystemTransport? transport;
  static final subscriptions = <StreamSubscription<Object?>>[];
}

Future<void> initializeSystemMedia() =>
    SystemMediaRuntime.initializing ??= _initializeSystemMedia().whenComplete(
      () => SystemMediaRuntime.initializing = null,
    );

Future<void> _initializeSystemMedia() async {
  if (SystemMediaRuntime.controller != null) return;
  MediaSessionController? controller;
  final engines = MediaEngineOwner([
    const MediaKitEngineFactory(),
    const AudioplayersEngineFactory(),
  ]);
  SystemMediaRuntime.engines = engines;
  try {
    // Keep the owner and its explicit selector alive if the default backend
    // cannot load. No second engine is selected without the user's command.
    await engines.select('media-kit');
    final mobileSession =
        kIsWeb ||
        const {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);
    final session = mobileSession ? await AudioSession.instance : null;
    controller = MediaSessionController(
      engines,
      activate: session == null ? null : () => session.setActive(true),
    );
    if (session != null) {
      await session.configure(const AudioSessionConfiguration.music());
    }
    final active = controller;
    try {
      SystemMediaRuntime.transport = await attachSystemTransport(active);
      SystemMediaRuntime.transportError = null;
    } catch (failure) {
      // In-app and mini playback remain available if the OS integration fails.
      SystemMediaRuntime.transportError = '$failure';
    }
    if (session != null) {
      SystemMediaRuntime.subscriptions.add(
        session.interruptionEventStream.listen(
          (event) => unawaited(active.interrupt(beginning: event.begin)),
        ),
      );
      SystemMediaRuntime.subscriptions.add(
        session.becomingNoisyEventStream.listen(
          (_) => unawaited(active.becameNoisy()),
        ),
      );
    }
    SystemMediaRuntime.controller = controller;
    SystemMediaRuntime.error = null;
  } catch (failure) {
    await controller?.close();
    if (controller == null) await engines.close();
    SystemMediaRuntime.error = '$failure';
  }
}

Future<void> retrySystemTransport() async {
  final controller = SystemMediaRuntime.controller;
  if (controller == null || SystemMediaRuntime.transport != null) return;
  try {
    SystemMediaRuntime.transport = await attachSystemTransport(controller);
    SystemMediaRuntime.transportError = null;
  } catch (failure) {
    SystemMediaRuntime.transportError = '$failure';
  }
}

@Riverpod(keepAlive: true)
MediaSessionController? systemMediaController(Ref ref) =>
    SystemMediaRuntime.controller;

Future<bool> prepareSystemMedia() async {
  try {
    await SystemMediaRuntime.controller?.stop();
    return true;
  } catch (error) {
    SystemMediaRuntime.error = '$error';
    return false;
  }
}

Future<void> disposeSystemMedia() async {
  await SystemMediaRuntime.initializing;
  for (final subscription in SystemMediaRuntime.subscriptions) {
    await subscription.cancel();
  }
  SystemMediaRuntime.subscriptions.clear();
  await SystemMediaRuntime.transport?.close();
  SystemMediaRuntime.transport = null;
  await SystemMediaRuntime.controller?.close();
  SystemMediaRuntime.controller = null;
  await SystemMediaRuntime.engines?.close();
  SystemMediaRuntime.engines = null;
}
