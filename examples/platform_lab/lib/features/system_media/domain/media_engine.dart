abstract interface class MediaEngine {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
  bool get playing;
  Duration get position;
  Duration get duration;
  double get volume;
  Future<void> open(String uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> close();
}
