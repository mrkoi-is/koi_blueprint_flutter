import 'package:media_kit/media_kit.dart';

/// Native VideoController reports texture readiness; readable pixels may lag
/// its initial signal and are validated by the screenshot adapter.
final class MediaFrameGate {
  MediaFrameGate(Player player);
  Future<void> wait(Future<void> controllerReady) => controllerReady;
  Future<void> close() async {}
}
