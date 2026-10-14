import 'dart:async';
import 'dart:typed_data';

import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';

/// Each owner has a bounded byte/entry/TTL cache and reference-counted flights.
final class ImageRepositoryImpl implements ImageRepository {
  ImageRepositoryImpl({
    required this.transport,
    required this.localReader,
    required this.assetReader,
    required this.validator,
    this.maxBytes = 8 * 1024 * 1024,
    this.cacheBytes = 16 * 1024 * 1024,
    this.cacheEntries = 32,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (maxBytes < 1 ||
        cacheBytes < 1 ||
        cacheEntries < 1 ||
        ttl <= Duration.zero) {
      throw ArgumentError('Invalid image limits');
    }
  }
  final HttpTransport transport;
  final LocalImageReader localReader;
  final Future<Uint8List> Function(String path) assetReader;
  final ImageValidator validator;
  final int maxBytes, cacheBytes, cacheEntries;
  final Duration ttl;
  final DateTime Function() _now;
  final _cache = <String, ({Uint8List bytes, DateTime expires})>{};
  final _pending = <String, _Flight>{};
  final _work = <Future<ImagePayload>>{};
  int _cachedBytes = 0;
  bool _closed = false;
  int _cacheGeneration = 0;
  Future<void>? _closing;
  @override
  Future<ImagePayload> load(
    ImageSource source, {
    required Cancellation cancellation,
  }) async {
    if (_closed) throw StateError('Image repository closed');
    cancellation.check();
    if (source is NetworkImageSource) return _network(source.uri, cancellation);
    final bytes = switch (source) {
      AssetImageSource(:final path) => await assetReader(path),
      MemoryImageSource() => source.bytes,
      LocalImageSource(:final key) => await localReader.read(
        key,
        maxBytes: maxBytes,
      ),
      NetworkImageSource() => throw StateError('unreachable'),
    };
    cancellation.check();
    await _validate(bytes);
    cancellation.check();
    return ImagePayload(bytes);
  }

  Future<void> _validate(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Image byte budget exceeded');
    }
    await validator.validate(bytes);
  }

  Future<ImagePayload> _network(Uri uri, Cancellation cancellation) async {
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
      throw ArgumentError('Image URL must be HTTP(S)');
    }
    final key = uri.toString();
    final cached = _cache.remove(key);
    if (cached != null) {
      _cachedBytes -= cached.bytes.length;
      if (_now().isBefore(cached.expires)) {
        _cache[key] = cached;
        _cachedBytes += cached.bytes.length;
        return ImagePayload(cached.bytes, fromCache: true);
      }
    }
    final flight = _pending.putIfAbsent(key, () {
      final flight = _Flight();
      flight.future = _fetch(uri, flight.cancellation);
      _work.add(flight.future);
      unawaited(
        flight.future.then<void>(
          (_) => _work.remove(flight.future),
          onError: (Object _, StackTrace _) {
            _work.remove(flight.future);
          },
        ),
      );
      return flight;
    });
    flight.readers++;
    final result = Completer<ImagePayload>();
    final detach = cancellation.onCancel(() {
      if (!result.isCompleted) result.completeError(const RequestCancelled());
    });
    unawaited(
      flight.future.then(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    try {
      return await result.future;
    } finally {
      detach();
      flight.readers--;
      if (flight.readers == 0) {
        flight.cancellation.cancel();
        if (identical(_pending[key], flight)) _pending.remove(key);
      }
    }
  }

  Future<ImagePayload> _fetch(Uri uri, Cancellation cancellation) async {
    final generation = _cacheGeneration;
    final response = await transport.open(uri, cancellation: cancellation);
    if (response.status != 200) {
      cancellation.cancel();
      throw StateError('Image HTTP ${response.status}');
    }
    final declared = int.tryParse(response.headers['content-length'] ?? '');
    if (declared != null && (declared < 1 || declared > maxBytes)) {
      cancellation.cancel();
      throw StateError('Image byte budget exceeded');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.body) {
      cancellation.check();
      if (bytes.length + chunk.length > maxBytes) {
        cancellation.cancel();
        throw StateError('Image byte budget exceeded');
      }
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    if (declared != null && data.length != declared) {
      throw StateError('Incomplete image response');
    }
    await _validate(data);
    cancellation.check();
    if (!_closed &&
        generation == _cacheGeneration &&
        data.length <= cacheBytes) {
      while (_cache.isNotEmpty &&
          (_cache.length >= cacheEntries ||
              _cachedBytes + data.length > cacheBytes)) {
        _cachedBytes -= _cache.remove(_cache.keys.first)!.bytes.length;
      }
      _cache[uri.toString()] = (bytes: data, expires: _now().add(ttl));
      _cachedBytes += data.length;
    }
    return ImagePayload(data);
  }

  @override
  void clear() {
    _cacheGeneration++;
    _cache.clear();
    _cachedBytes = 0;
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final flights = List.of(_pending.values);
    for (final flight in flights) {
      flight.cancellation.cancel();
    }
    await Future.wait(
      List.of(_work).map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
    _pending.clear();
    clear();
    localReader.close();
    await transport.close();
  }
}

final class _Flight {
  final cancellation = Cancellation();
  late final Future<ImagePayload> future;
  int readers = 0;
}
