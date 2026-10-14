import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/domain/system_transport.dart';
import 'package:platform_lab/features/system_media/data/system_transport_web.dart'
    as shared;

Future<SystemTransport> attach(MediaSessionController controller) async {
  if (Platform.isLinux) AudioServiceMpris.registerWith();
  if (!Platform.isWindows) return shared.attach(controller);
  await SMTCWindows.initialize();
  return WindowsSystemTransport(
    controller,
    SMTCWindows(
      enabled: false,
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        stopEnabled: true,
        nextEnabled: false,
        prevEnabled: false,
        fastForwardEnabled: true,
        rewindEnabled: true,
      ),
    ),
  );
}

class WindowsSystemTransport implements SystemTransport {
  WindowsSystemTransport(this.controller, this.smtc) {
    _buttons = smtc.buttonPressStream.listen((button) {
      switch (button) {
        case PressedButton.play:
          unawaited(controller.play());
        case PressedButton.pause:
          unawaited(controller.pause());
        case PressedButton.stop:
          unawaited(controller.stop());
        case PressedButton.fastForward:
          unawaited(
            controller.seek(
              controller.engine.position + const Duration(seconds: 10),
            ),
          );
        case PressedButton.rewind:
          unawaited(
            controller.seek(
              controller.engine.position - const Duration(seconds: 10),
            ),
          );
        default:
          break;
      }
    });
    _state = controller.playbackState.listen(
      (state) => unawaited(_publish(state)),
    );
    _metadata = controller.mediaItem.listen((item) {
      if (item != null) {
        unawaited(
          smtc.updateMetadata(
            MusicMetadata(
              title: item.title,
              album: item.album,
              artist: item.artist,
            ),
          ),
        );
      }
    });
  }
  final MediaSessionController controller;
  final SMTCWindows smtc;
  late final StreamSubscription<PressedButton> _buttons;
  late final StreamSubscription<PlaybackState> _state;
  late final StreamSubscription<MediaItem?> _metadata;
  Future<void> _publish(PlaybackState state) async {
    if (state.processingState == AudioProcessingState.idle) {
      await smtc.disableSmtc();
      return;
    }
    await smtc.enableSmtc();
    await smtc.setPlaybackStatus(
      state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
    );
    await smtc.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: controller.engine.duration.inMilliseconds,
        positionMs: controller.engine.position.inMilliseconds,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _buttons.cancel();
    await _state.cancel();
    await _metadata.cancel();
    await smtc.disableSmtc();
    await smtc.dispose();
  }
}
