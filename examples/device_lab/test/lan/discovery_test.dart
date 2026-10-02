@TestOn('vm')
library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_lab/features/devices/data/device_discovery_native.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _Action<T extends BonsoirEvent> extends BonsoirAction<T> {
  final events = StreamController<T>.broadcast();
  bool failStart = false;
  int starts = 0;
  int stops = 0;
  @override
  bool isReady = false;
  @override
  bool isStopped = false;
  @override
  Stream<T> get eventStream => events.stream;
  @override
  Future<void> initialize() async => isReady = !isStopped;
  @override
  Future<void> start() async {
    if (isStopped) throw StateError('Native action was already stopped');
    starts++;
    if (failStart) throw StateError('permission denied');
  }

  @override
  Future<void> stop() async {
    stops++;
    isStopped = true;
    isReady = false;
  }
}

class _DiscoveryAction extends _Action<BonsoirDiscoveryEvent>
    with ServiceResolver {
  final resolved = <BonsoirService>[];
  @override
  void resolveService(BonsoirService service) => resolved.add(service);
  @override
  bool supportsMdnsHostname() => false;
}

class _Platform extends BonsoirPlatformInterface {
  bool failFirstDiscovery = false;
  bool failBroadcast = false;
  final discoveries = <_DiscoveryAction>[];
  final broadcasts = <_Action<BonsoirBroadcastEvent>>[];
  BonsoirService? advertised;
  @override
  BonsoirAction<BonsoirDiscoveryEvent> createDiscoveryAction(
    String type, {
    bool printLogs = true,
  }) {
    expect(type, deviceServiceType);
    final action = _DiscoveryAction()
      ..failStart = failFirstDiscovery && discoveries.isEmpty;
    discoveries.add(action);
    return action;
  }

  @override
  BonsoirAction<BonsoirBroadcastEvent> createBroadcastAction(
    BonsoirService service, {
    bool printLogs = true,
  }) {
    advertised = service;
    final action = _Action<BonsoirBroadcastEvent>()..failStart = failBroadcast;
    broadcasts.add(action);
    return action;
  }
}

void main() {
  late _Platform platform;
  setUp(() {
    final previous = BonsoirPlatformInterface.instance;
    platform = _Platform();
    BonsoirPlatformInterface.instance = platform;
    addTearDown(() async {
      BonsoirPlatformInterface.instance = previous;
      for (final action in <_Action<BonsoirEvent>>[
        ...platform.discoveries,
        ...platform.broadcasts,
      ]) {
        await action.events.close();
      }
    });
  });

  test('failed native discovery can retry with a fresh action and resolve valid peers', () async {
    platform.failFirstDiscovery = true;
    final discovery = createDeviceDiscovery();
    final received = <List<DiscoveredDevice>>[];
    final subscription = discovery.changes.listen(received.add);
    addTearDown(subscription.cancel);
    addTearDown(discovery.close);
    await expectLater(discovery.start(), throwsStateError);
    expect(platform.discoveries.first.stops, 1);
    await discovery.start();
    await discovery.start();
    expect(platform.discoveries.length, 2);
    final action = platform.discoveries.last;
    expect(action.starts, 1);
    final found = BonsoirService(
      name: 'peer',
      type: deviceServiceType,
      port: 7654,
    );
    action.events.add(BonsoirDiscoveryServiceFoundEvent(service: found));
    await Future<void>.delayed(Duration.zero);
    expect(action.resolved, [found]);
    final valid = BonsoirService(
      name: 'peer',
      type: deviceServiceType,
      port: 7654,
      hostAddresses: ['127.0.0.1'],
      attributes: {'version': '1'},
    );
    action.events.add(BonsoirDiscoveryServiceResolvedEvent(service: valid));
    await Future<void>.delayed(Duration.zero);
    expect(
      received.single.single.uri.toString(),
      'ws://127.0.0.1:7654/commands',
    );
    action.events.add(BonsoirDiscoveryServiceLostEvent(service: valid));
    await Future<void>.delayed(Duration.zero);
    expect(received.last, isEmpty);
    await discovery.close();
    await discovery.close();
    expect(action.stops, 1);
    await expectLater(discovery.start(), throwsStateError);
  });

  test('advertisement exposes the finite protocol and cleans failure or repeated close', () async {
    platform.failBroadcast = true;
    await expectLater(advertiseDevice('local', 8080), throwsStateError);
    expect(platform.broadcasts.single.stops, 1);
    platform.failBroadcast = false;
    final advertisement = await advertiseDevice('local', 8081);
    expect(platform.advertised!.port, 8081);
    expect(platform.advertised!.attributes, {'version': '1'});
    await advertisement.close();
    await advertisement.close();
    expect(platform.broadcasts.last.stops, 1);
  });
}
