import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

export 'package:device_lab/features/devices/domain/device_contracts.dart'
    show DeviceConnectionState;

final class PairedDeviceClient {
  final _changes = StreamController<DeviceConnectionState>.broadcast();
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _prefix = Random.secure().nextInt(1 << 32).toRadixString(16);
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  Uri? _uri;
  String? _code;
  String? _token;
  String? _generation;
  int _counter = 0;
  int _connection = 0;
  int _attempt = 0;
  bool _closed = false;
  DeviceConnectionState state = DeviceConnectionState.disconnected;
  Stream<DeviceConnectionState> get changes => _changes.stream;
  void _set(DeviceConnectionState next) {
    state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<void> connect(Uri uri, String code) async {
    if (_closed) throw StateError('Client closed');
    if (!['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('WebSocket address required');
    }
    _uri = uri;
    _code = code;
    final connection = ++_connection;
    _reconnect?.cancel();
    await _disconnect();
    if (_closed || connection != _connection) {
      throw StateError('Connection superseded');
    }
    _set(DeviceConnectionState.connecting);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_closed || connection != _connection) {
        await channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(
        _receive,
        onError: (Object error) => _lost(error, connection),
        onDone: () => _lost(StateError('Connection closed'), connection),
      );
      final reply = await _request({'command': 'pair', 'code': code});
      if (_closed || connection != _connection) {
        throw StateError('Connection superseded');
      }
      _token = reply['token'] as String;
      _generation = reply['generation'] as String;
      _attempt = 0;
      _set(DeviceConnectionState.paired);
    } catch (error) {
      if (connection == _connection && !_closed) {
        _set(DeviceConnectionState.failed);
        await _disconnect();
      }
      rethrow;
    }
  }

  void _receive(dynamic event) {
    try {
      final value = jsonDecode(event as String) as Map<String, dynamic>;
      if (value['version'] != 1) {
        throw const FormatException('Protocol version changed');
      }
      final pending = _pending.remove(value['id']);
      if (pending == null) return;
      if (value['error'] != null) {
        pending.completeError(StateError('${value['error']}'));
      } else {
        pending.complete(Map<String, Object?>.from(value));
      }
    } catch (error) {
      _lost(error, _connection);
    }
  }

  Future<Map<String, Object?>> _request(Map<String, Object?> body) async {
    final channel = _channel;
    if (channel == null) throw StateError('No connection');
    final id = '${_prefix}_${++_counter}';
    final result = Completer<Map<String, Object?>>();
    _pending[id] = result;
    channel.sink.add(jsonEncode({'version': 1, 'id': id, ...body}));
    try {
      return await result.future.timeout(const Duration(seconds: 5));
    } finally {
      _pending.remove(id);
    }
  }

  Future<Map<String, Object?>> execute(DeviceCommand command) async {
    if (state != DeviceConnectionState.paired) {
      throw StateError('Pair a device first');
    }
    final result = await _request({
      'command': command.name,
      'token': _token,
      'generation': _generation,
    });
    if (result['generation'] != _generation) {
      throw StateError('Stale device session');
    }
    return Map<String, Object?>.from(result['result'] as Map);
  }

  void _lost(Object error, int connection) {
    if (_closed || connection != _connection || _reconnect?.isActive == true) {
      return;
    }
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
    _set(DeviceConnectionState.reconnecting);
    _reconnect = Timer(
      Duration(seconds: min(30, 1 << min(_attempt++, 5))),
      () async {
        if (_closed) return;
        try {
          await connect(_uri!, _code!);
        } catch (error) {
          _lost(error, _connection);
        }
      },
    );
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _token = null;
    _generation = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Disconnected'));
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_connection;
    _reconnect?.cancel();
    await _disconnect();
    _set(DeviceConnectionState.closed);
    await _changes.close();
  }
}
