import 'package:flutter/foundation.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';

class FakeMediaEngine extends ChangeNotifier implements MediaEngine {
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 120);
  @override
  double volume = .7;
  int opens = 0;
  bool closed = false;
  @override
  Future<void> open(String uri) async {
    opens++;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closed = true;
    dispose();
  }
}
