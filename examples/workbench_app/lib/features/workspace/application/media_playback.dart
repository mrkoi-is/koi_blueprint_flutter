import 'package:flutter/foundation.dart';

/// Playback contract. The URI and its lifetime never enter a domain model.
final class PreviewSource {
  const PreviewSource({required this.uri, required this.release});
  final String uri;
  final Future<void> Function() release;
}

abstract interface class MediaPlayback implements Listenable {
  bool get playing;
  Duration get position;
  Duration get duration;
  double get volume;
  Stream<String> get errors;
  Future<void> open(String uri);
  Future<void> get firstFrame;
  Future<Uint8List?> screenshot();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> close();
}

typedef MediaPlaybackFactory = MediaPlayback Function();
typedef PreviewSourceFactory = Future<PreviewSource> Function(String key);
