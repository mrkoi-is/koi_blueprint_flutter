import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Constructed once per player by bootstrap, retained across layout changes.
Widget createMediaKitSurface(VideoController controller) => Video(
  key: GlobalKey(debugLabel: 'persistent-video-surface'),
  controller: controller,
  controls: null,
);
