import 'package:koi_core/koi_core.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';
import 'package:platform_lab/features/system_media/domain/media_engine_factory.dart';

/// A stable media port shared by the main view, mini view and OS controls.
/// Selection is explicit. An unavailable or failed candidate never silently
/// replaces the current engine. Commands and replacement are serialized.
class MediaEngineOwner implements MediaEngine {
  MediaEngineOwner(Iterable<MediaEngineFactory> factories)
    : _factories = {for (final factory in factories) factory.id: factory};

  final Map<String, MediaEngineFactory> _factories;
  final Map<String, CapabilityAvailability> _availability = {};
  final _listeners = <void Function()>{};
  final _retired = <MediaEngine>[];
  MediaEngine? _engine;
  String? selectedId;
  String? error;
  String? _uri;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;

  Iterable<String> get engineIds => _factories.keys;
  Map<String, CapabilityAvailability> get availability =>
      Map.unmodifiable(_availability);
  bool get isReady => _engine != null && !_closed;

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _tail.then((_) {
      if (_closed) throw StateError('Media engine owner is closed');
      return action();
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<bool> select(String id) => _serial(() async {
    final factory = _factories[id];
    if (factory == null) {
      error = 'Unknown media engine: $id';
      _notify();
      return false;
    }
    MediaEngine? candidate;
    final previous = _engine;
    var previousPaused = false;
    var resumePrevious = false;
    try {
      final availability = await factory.probe();
      _availability[id] = availability;
      if (!availability.isAvailable) {
        error = availability.reason ?? 'Media engine unavailable';
        _notify();
        return false;
      }
      candidate = await factory.create();
      if (_uri case final uri?) await candidate.open(uri);
      if (previous != null) {
        // Keep the previous engine playing during candidate loading, then
        // freeze its position while the new backend confirms the seek.
        resumePrevious = previous.playing;
        // A platform pause can change native state before returning an error.
        // Restore the captured playback intent on that partial failure too.
        previousPaused = true;
        await previous.pause();
        await candidate.setVolume(previous.volume);
        if (_uri != null) await candidate.seek(previous.position);
        if (resumePrevious) await candidate.play();
      }
      // Publishing the new port is the commit point. Until here the old engine
      // remains owned and can continue after any probe/create/open/play failure.
      previous?.removeListener(_notify);
      _engine = candidate;
      selectedId = id;
      candidate.addListener(_notify);
      candidate = null;
      error = null;
      if (previous != null) {
        try {
          await previous.close();
        } catch (failure) {
          _retired.add(previous);
          error = 'Previous engine cleanup failed: $failure';
        }
      }
      _notify();
      return true;
    } catch (failure) {
      _availability[id] = CapabilityAvailability.unavailable('$failure');
      error = '$failure';
      if (candidate != null) {
        try {
          await candidate.close();
        } catch (_) {
          _retired.add(candidate);
        }
      }
      if (previousPaused && resumePrevious && previous != null) {
        try {
          await previous.play();
        } catch (restoreFailure) {
          error = '$failure; previous playback resume failed: $restoreFailure';
        }
      }
      _notify();
      return false;
    }
  });

  MediaEngine get _active =>
      _engine ?? (throw StateError('No media engine has been selected'));
  @override
  bool get playing => _engine?.playing ?? false;
  @override
  Duration get position => _engine?.position ?? Duration.zero;
  @override
  Duration get duration => _engine?.duration ?? Duration.zero;
  @override
  double get volume => _engine?.volume ?? 1;
  @override
  Future<void> open(String uri) => _serial(() async {
    await _active.open(uri);
    _uri = uri;
  });
  @override
  Future<void> play() => _serial(() => _active.play());
  @override
  Future<void> pause() => _serial(() async {
    // An unavailable startup backend must not prevent graceful exit or an OS
    // stop command while the user is choosing an explicit alternative.
    await _engine?.pause();
  });
  @override
  Future<void> seek(Duration position) => _serial(() => _active.seek(position));
  @override
  Future<void> setVolume(double volume) =>
      _serial(() => _active.setVolume(volume));
  @override
  void addListener(void Function() listener) => _listeners.add(listener);
  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notify() {
    if (_closed) return;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _tail;
    _engine?.removeListener(_notify);
    final engines = [..._retired, ?_engine];
    _engine = null;
    _listeners.clear();
    Object? failure;
    for (final engine in engines) {
      try {
        await engine.close();
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }
}
