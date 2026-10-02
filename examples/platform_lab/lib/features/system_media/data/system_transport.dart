import 'package:platform_lab/features/system_media/application/media_session_controller.dart';
import 'package:platform_lab/features/system_media/domain/system_transport.dart';
import 'package:platform_lab/features/system_media/data/system_transport_web.dart'
    if (dart.library.io) 'package:platform_lab/features/system_media/data/system_transport_native.dart'
    as platform;

Future<SystemTransport> attachSystemTransport(
  MediaSessionController controller,
) => platform.attach(controller);
