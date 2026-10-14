import 'package:audio_service/audio_service.dart';
import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/domain/system_transport.dart';

Future<SystemTransport> attach(MediaSessionController controller) async {
  await AudioService.init(
    builder: () => controller,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'workspace.media',
      androidNotificationChannelName: 'Media playback',
      androidNotificationOngoing: true,
    ),
  );
  return _AudioServiceTransport(controller);
}

class _AudioServiceTransport implements SystemTransport {
  _AudioServiceTransport(this.controller);
  final MediaSessionController controller;
  @override
  Future<void> close() => controller.stop();
}
