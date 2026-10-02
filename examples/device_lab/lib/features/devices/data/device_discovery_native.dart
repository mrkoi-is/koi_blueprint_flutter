import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';

const deviceServiceType = '_koi-device._tcp';
DeviceDiscovery createDeviceDiscovery() => BonjourDeviceDiscovery();

final class BonjourDeviceDiscovery implements DeviceDiscovery {
  var _discovery = BonsoirDiscovery(type: deviceServiceType);
  final _changes = StreamController<List<DiscoveredDevice>>.broadcast();
  final _devices = <String, DiscoveredDevice>{};
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  bool _started = false;
  bool _closed = false;
  @override
  Stream<List<DiscoveredDevice>> get changes => _changes.stream;
  @override
  Future<void> start() async {
    if (_closed) throw StateError('Discovery is closed');
    if (_started) return;
    // Bonsoir actions cannot restart after stop, including failure cleanup.
    if (_discovery.isStopped) {
      _discovery = BonsoirDiscovery(type: deviceServiceType);
    }
    _started = true;
    try {
      await _discovery.initialize();
      if (_closed) {
        await _discovery.stop();
        return;
      }
      _subscription = _discovery.eventStream!.listen((event) {
        final service = event.service;
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            service?.resolve(_discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent():
            final address = service?.hostAddresses.firstOrNull;
            if (service != null &&
                address != null &&
                service.port > 0 &&
                service.attributes['version'] == '1') {
              _devices[service.name] = DiscoveredDevice(
                service.name,
                Uri(
                  scheme: 'ws',
                  host: address,
                  port: service.port,
                  path: '/commands',
                ),
              );
              _changes.add(List.unmodifiable(_devices.values));
            }
          case BonsoirDiscoveryServiceLostEvent():
            _devices.remove(service?.name);
            _changes.add(List.unmodifiable(_devices.values));
          default:
            break;
        }
      }, onError: _changes.addError);
      await _discovery.start();
    } catch (_) {
      _started = false;
      await _subscription?.cancel();
      _subscription = null;
      if (_discovery.isReady && !_discovery.isStopped) await _discovery.stop();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    if (_started && _discovery.isReady) await _discovery.stop();
    await _changes.close();
  }
}

Future<DeviceAdvertisement> advertiseDevice(String name, int port) async {
  final broadcast = BonsoirBroadcast(
    service: BonsoirService(
      name: name,
      type: deviceServiceType,
      port: port,
      attributes: {'version': '1'},
    ),
  );
  await broadcast.initialize();
  try {
    await broadcast.start();
    return _Advertisement(broadcast);
  } catch (_) {
    await broadcast.stop();
    rethrow;
  }
}

final class _Advertisement implements DeviceAdvertisement {
  _Advertisement(this.broadcast);
  final BonsoirBroadcast broadcast;
  bool closed = false;
  @override
  Future<void> close() async {
    if (!closed) {
      closed = true;
      await broadcast.stop();
    }
  }
}
