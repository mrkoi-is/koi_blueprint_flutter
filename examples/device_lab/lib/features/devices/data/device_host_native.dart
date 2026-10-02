import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_lab/features/devices/application/device_protocol.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

bool get canHostDevices =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;
Future<DeviceHost> startDeviceHost(
  DeviceCommandTarget target, {
  String address = '127.0.0.1',
  int port = 0,
}) async {
  if (!canHostDevices) {
    throw UnsupportedError(
      'This sample hosts on desktop; mobile is a foreground client',
    );
  }
  final server = await HttpServer.bind(address, port);
  return SocketDeviceHost(server, PairedDeviceProtocol(target));
}

final class SocketDeviceHost implements DeviceHost {
  SocketDeviceHost(this.server, this.protocol) {
    _subscription = server.listen(_handle);
  }
  final HttpServer server;
  final PairedDeviceProtocol protocol;
  final _sockets = <WebSocket>{};
  final _operations = <Future<void>>{};
  late final StreamSubscription<HttpRequest> _subscription;
  bool _closed = false;
  @override
  Uri get uri => Uri(
    scheme: 'ws',
    host: server.address.address,
    port: server.port,
    path: '/commands',
  );
  @override
  String get pairingCode => protocol.pairingCode;

  void _handle(HttpRequest request) {
    final operation = _serve(request);
    _operations.add(operation);
    unawaited(operation.whenComplete(() => _operations.remove(operation)));
  }

  Future<void> _serve(HttpRequest request) async {
    if (_closed ||
        request.uri.path != '/commands' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      try {
        await for (final value in socket) {
          if (_closed) break;
          String? id;
          try {
            if (value is! String) {
              throw const FormatException('Text JSON messages required');
            }
            if (value.length <= 16 * 1024) {
              final json = jsonDecode(value);
              if (json is Map && json['id'] is String) {
                id = json['id'] as String;
              }
            }
            final response = await protocol.receive(value);
            socket.add(jsonEncode(response));
          } catch (error) {
            socket.add(jsonEncode({'version': 1, 'id': id, 'error': '$error'}));
          }
        }
      } finally {
        _sockets.remove(socket);
        await socket.close();
      }
    } on WebSocketException {
      // Disconnected peers have no outstanding owned resources after finally.
    } on HttpException {
      // A failed HTTP upgrade closes with the request's connection.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    for (final socket in List.of(_sockets)) {
      await socket.close(WebSocketStatus.goingAway);
    }
    await server.close(force: true);
    await Future.wait(List.of(_operations));
  }
}
