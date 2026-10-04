import 'package:flutter/widgets.dart';
import 'package:workbench_app/features/workspace/application/media_playback.dart';

/// A borrowed display handle. It owns neither playback nor business state.
/// The widget (and its key) stays stable while that player remains selected.
final class MediaSurfaceHandle {
  MediaPlayback? _identity;
  Widget? _surface;
  void attach(MediaPlayback identity, Widget surface) {
    _identity = identity;
    _surface = surface;
  }

  Widget? surfaceFor(MediaPlayback identity) =>
      identical(identity, _identity) ? _surface : null;

  void clear(MediaPlayback identity) {
    if (identical(identity, _identity)) {
      _identity = null;
      _surface = null;
    }
  }
}
