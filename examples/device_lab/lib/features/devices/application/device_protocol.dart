import 'dart:convert';
import 'dart:math';

import 'package:device_lab/features/devices/domain/device_contracts.dart';

/// Finite commands only; no evaluation, shell execution or file synchronization.
final class PairedDeviceProtocol {
  PairedDeviceProtocol(this.target, {String? pairingCode})
    : pairingCode =
          pairingCode ?? (100000 + Random.secure().nextInt(900000)).toString(),
      generation = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  final DeviceCommandTarget target;
  final String pairingCode;
  final String generation;
  final _responses =
      <String, ({String request, Future<Map<String, Object?>> response})>{};
  int _failedPairings = 0;
  String? _token;

  Future<Map<String, Object?>> receive(String raw) async {
    if (raw.length > 16 * 1024) {
      throw const FormatException('Message too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Incompatible protocol version');
    }
    final id = decoded['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid correlation ID');
    }
    if (decoded['command'] == 'pair') {
      if (_failedPairings >= 5) {
        throw StateError('Pairing limit reached; start a new host session');
      }
      if (decoded['code'] != pairingCode) {
        _failedPairings++;
        throw StateError('Invalid pairing code');
      }
      _token ??= List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      return {
        'version': 1,
        'id': id,
        'generation': generation,
        'token': _token,
      };
    }
    if (_token == null ||
        decoded['token'] != _token ||
        decoded['generation'] != generation) {
      throw StateError('Current paired session required');
    }
    final name = decoded['command'];
    final command = DeviceCommand.values
        .where((item) => item.name == name)
        .firstOrNull;
    if (command == null) throw const FormatException('Unknown device command');
    final identity = jsonEncode({'command': name, 'generation': generation});
    final existing = _responses[id];
    if (existing != null) {
      if (existing.request != identity) {
        throw const FormatException(
          'Correlation ID reused for another command',
        );
      }
      return existing.response;
    }
    final response = target
        .execute(command)
        .then(
          (result) => <String, Object?>{
            'version': 1,
            'id': id,
            'generation': generation,
            'result': result,
          },
        );
    _responses[id] = (request: identity, response: response);
    if (_responses.length > 256) _responses.remove(_responses.keys.first);
    return response;
  }
}
