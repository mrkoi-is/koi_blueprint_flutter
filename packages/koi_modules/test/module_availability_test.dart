import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_modules/koi_modules.dart';

KoiModule<String> contribution(
  String id, {
  Set<String> capabilities = const {'message.read'},
  FutureOr<CapabilityAvailability> Function()? check,
  FutureOr<String> Function(ModuleSessionContext)? create,
}) => KoiModule(
  id: id,
  routes: const [],
  navigation: const [],
  capabilities: capabilities,
  checkAvailability: check,
  createSession: create ?? (_) => id,
);

void main() {
  test('capability descriptors are immutable and validated, old modules remain compatible', () {
    final declared = {'message.read'};
    final module = contribution('alpha', capabilities: declared);
    declared.clear();
    expect(module.capabilities, {'message.read'});
    expect(() => module.capabilities.add('changed'), throwsUnsupportedError);
    expect(
      () => KoiModuleCatalog([
        contribution('invalid', capabilities: {' '}),
      ]),
      throwsArgumentError,
    );
    final old = KoiModule<String>(
      id: 'legacy',
      routes: [],
      navigation: [],
      createSession: (_) => 'works',
    );
    expect(old.capabilities, isEmpty);
    expect(old.checkAvailability, isNull);
  });

  test('unsupported platform skips session construction and another module remains usable', () async {
    var created = 0;
    final runtime = KoiModuleRuntime(
      KoiModuleCatalog([
        contribution(
          'unsupported',
          check: () => const CapabilityAvailability.unsupported('此平台不支持原生引擎'),
          create: (_) {
            created++;
            return 'bad';
          },
        ),
        contribution('fallback'),
      ]),
    );
    addTearDown(runtime.disposeAsync);
    await expectLater(
      runtime.activate('unsupported'),
      throwsA(isA<ModuleUnavailableException>()),
    );
    expect(created, 0);
    expect(runtime.state.availability?.status, CapabilityStatus.unsupported);
    expect(runtime.state.session, isNull);
    expect((await runtime.activate('fallback')).capability, 'fallback');
  });

  test(
    'configuration can recover without replacing the catalog or router',
    () async {
      var configured = false;
      var created = 0;
      final catalog = KoiModuleCatalog([
        contribution(
          'beta',
          check: () => configured
              ? const CapabilityAvailability.available()
              : const CapabilityAvailability.unavailable('先配置资源'),
          create: (_) {
            created++;
            return 'beta';
          },
        ),
      ]);
      final runtime = KoiModuleRuntime(catalog);
      addTearDown(runtime.disposeAsync);
      await expectLater(
        runtime.activate('beta'),
        throwsA(isA<ModuleUnavailableException>()),
      );
      expect(runtime.state.availability?.reason, '先配置资源');
      expect(created, 0);
      configured = true;
      expect((await runtime.activate('beta')).capability, 'beta');
      expect(runtime.catalog, same(catalog));
      expect(created, 1);
      expect(runtime.state.availability?.isAvailable, isTrue);
    },
  );

  test('initialization failure releases owned resources and retry uses a fresh session', () async {
    var fail = true;
    var cleanups = 0;
    final runtime = KoiModuleRuntime(
      KoiModuleCatalog([
        contribution(
          'engine',
          create: (context) {
            context.onDispose(() => cleanups++);
            if (fail) throw StateError('native resource failed');
            return 'live';
          },
        ),
      ]),
    );
    await expectLater(runtime.activate('engine'), throwsStateError);
    expect(cleanups, 1);
    expect(runtime.state.availability?.status, CapabilityStatus.unavailable);
    expect(runtime.state.availability?.diagnostic, isA<StateError>());
    fail = false;
    expect((await runtime.activate('engine')).capability, 'live');
    await runtime.disposeAsync();
    expect(cleanups, 2);
  });

  test(
    'a late availability completion cannot initialize a replaced module',
    () async {
      final started = Completer<void>();
      final ready = Completer<CapabilityAvailability>();
      var firstCreated = 0;
      final runtime = KoiModuleRuntime(
        KoiModuleCatalog([
          contribution(
            'slow',
            check: () {
              started.complete();
              return ready.future;
            },
            create: (_) {
              firstCreated++;
              return 'stale';
            },
          ),
          contribution('new'),
        ]),
      );
      addTearDown(runtime.disposeAsync);
      final pending = runtime.activate('slow');
      final rejected = expectLater(
        pending,
        throwsA(isA<StaleModuleSessionException>()),
      );
      await started.future;
      final next = runtime.activate('new');
      ready.complete(const CapabilityAvailability.available());
      await rejected;
      expect((await next).moduleId, 'new');
      expect(firstCreated, 0);
    },
  );
}
