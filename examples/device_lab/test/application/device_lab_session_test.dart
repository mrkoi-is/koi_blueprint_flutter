import 'package:device_lab/features/devices/application/device_lab_session.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  test('startup queues cold link, never hosts/discovers, and draft failures retain the event', () async {
    final settings = MemorySettings();
    final discovery = FakeDiscovery();
    final links = FakeLinks()..initialUri = Uri.parse('koi://tasks');
    var hosts = 0;
    final session = DeviceLabSession(
      settings: settings,
      discovery: discovery,
      links: links,
      startHost: (_, {address = '127.0.0.1', port = 0}) async {
        hosts++;
        return _Host();
      },
      advertise: (_, _) async => _Advertisement(),
      importFile: (_) async =>
          const ImportedDocument('real.txt', 'Imported body'),
    );
    await session.initialize();
    expect(hosts, 0);
    expect(discovery.starts, 0);
    expect(session.state.pendingIntents, 1);
    await session.skipOnboarding();
    expect(session.state.activeTab, 'tasks');
    expect(session.state.pendingIntents, 0);
    session.edit('Unsaved content');
    expect(
      await session.receiveUri(Uri.parse('koi://document?id=welcome')),
      IncomingResult.blocked,
    );
    settings.fail = true;
    await expectLater(session.saveDraft(), throwsStateError);
    expect(session.state.dirty, true);
    expect(session.state.pendingIntents, 1);
    expect(session.state.draft, 'Unsaved content');
    settings.fail = false;
    await session.saveDraft();
    expect(session.state.activeTab, 'documents');
    expect(session.state.pendingIntents, 0);
    await session.receiveUri(Uri.file('/tmp/fixture.txt'));
    expect(session.state.documents.length, 2);
    expect(session.state.draft, 'Imported body');
    final summary = await session.execute(DeviceCommand.pauseTask);
    expect((summary['task'] as Map)['paused'], true);
    expect((summary['documents'] as List).length, 2);
    expect(summary.toString(), isNot(contains('Unsaved content')));
    await session.close();
    await session.close();
    await links.events.close();
    expect(settings.closed, true);
    expect(discovery.events.isClosed, true);
  });
  test(
    'failed advertising closes the opened server and the owner can retry',
    () async {
      final settings = MemorySettings();
      final discovery = FakeDiscovery();
      final hosts = <_Host>[];
      var fail = true;
      final session = DeviceLabSession(
        settings: settings,
        discovery: discovery,
        startHost: (_, {address = '127.0.0.1', port = 0}) async {
          final host = _Host();
          hosts.add(host);
          return host;
        },
        advertise: (_, _) async {
          if (fail) throw StateError('Bonjour not available');
          return _Advertisement();
        },
        importFile: (_) async => const ImportedDocument('', ''),
      );
      await session.initialize();
      expect(await session.act(() => session.host(localNetwork: true)), false);
      expect(hosts.single.closed, true);
      expect(session.state.hostUri, isNull);
      fail = false;
      await session.host(localNetwork: true);
      expect(session.state.hostUri, isNotNull);
      await session.close();
      expect(hosts.every((host) => host.closed), true);
    },
  );
}

final class _Host implements DeviceHost {
  bool closed = false;
  @override
  Uri get uri => Uri.parse('ws://127.0.0.1:1234/commands');
  @override
  String get pairingCode => '123456';
  @override
  Future<void> close() async => closed = true;
}

final class _Advertisement implements DeviceAdvertisement {
  @override
  Future<void> close() async {}
}
