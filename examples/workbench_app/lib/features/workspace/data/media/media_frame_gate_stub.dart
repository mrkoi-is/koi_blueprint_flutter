import 'package:media_kit/media_kit.dart';

/// Native VideoController completes after a texture frame has been rendered.
final class MediaFrameGate {
  MediaFrameGate(Player player);
  Future<void> wait(Future<void> controllerReady) => controllerReady;
  Future<void> close() async {}
}
