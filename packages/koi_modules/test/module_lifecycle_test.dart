import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_modules/koi_modules.dart';

KoiModule<String> module(
  String id, {
  FutureOr<String> Function(ModuleSessionContext)? create,
  List<RouteBase>? routes,
  List<ModuleNavigationItem>? navigation,
}) => KoiModule(
  id: id,
  routes: routes ?? [route('/$id')],
  navigation:
      navigation ??
      [ModuleNavigationItem(id: '$id.home', label: id, location: '/$id')],
  createSession: create ?? (_) => id,
);

GoRoute route(String path, {String? name, List<RouteBase> routes = const []}) =>
    GoRoute(
      path: path,
      name: name,
      routes: routes,
      builder: (_, _) => const SizedBox(),
    );

void main() {
  group('immutable compile-time catalog', () {
    test('preserves contributions without a global registry', () {
      final alpha = module('alpha');
      final source = [alpha, module('beta')];
      final catalog = KoiModuleCatalog(source);
      source.clear();
      expect(catalog.modules, hasLength(2));
      expect(catalog.routes, hasLength(2));
      expect(catalog.module('alpha'), same(alpha));
      expect(() => catalog.modules.clear(), throwsUnsupportedError);
      expect(() => alpha.routes.clear(), throwsUnsupportedError);
      expect(() => alpha.navigation.clear(), throwsUnsupportedError);
      expect(() => catalog.module('missing'), throwsArgumentError);
    });

    test('rejects empty or duplicate module and navigation ids', () {
      expect(() => KoiModuleCatalog([module('')]), throwsArgumentError);
      expect(
        () => KoiModuleCatalog([module('alpha'), module('alpha')]),
        throwsArgumentError,
      );
      for (final id in ['', 'alpha.home']) {
        expect(
          () => KoiModuleCatalog([
            module('alpha'),
            module(
              'beta',
              navigation: [
                ModuleNavigationItem(id: id, label: 'Beta', location: '/beta'),
              ],
            ),
          ]),
          throwsArgumentError,
        );
      }
      expect(
        () => KoiModuleCatalog([
          module(
            'alpha',
            navigation: [
              const ModuleNavigationItem(
                id: 'home',
                label: 'Home',
                location: 'relative',
              ),
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate full paths through shells and route names', () {
      expect(
        () => KoiModuleCatalog([
          module(
            'alpha',
            routes: [
              ShellRoute(
                builder: (_, _, child) => child,
                routes: [
                  route('/alpha', routes: [route('detail')]),
                ],
              ),
            ],
          ),
          module('beta', routes: [route('/alpha/detail')]),
        ]),
        throwsArgumentError,
      );
      expect(
        () => KoiModuleCatalog([
          module('alpha', routes: [route('/alpha', name: 'home')]),
          module('beta', routes: [route('/beta', name: 'home')]),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('session ownership', () {
    test('guard preserves active values and errors', () async {
      final context = ModuleSessionContext(moduleId: 'alpha', generation: 7);
      expect(await context.guard(Future.value('value')), 'value');
      final error = StateError('real failure');
      await expectLater(
        context.guard(Future<String>.error(error)),
        throwsA(same(error)),
      );
      await context.disposeAsync();
      expect(context.isActive, isFalse);
    });

    test(
      'late success and failure are both rejected after invalidation',
      () async {
        final context = ModuleSessionContext(moduleId: 'alpha', generation: 7);
        final success = Completer<String>();
        final failure = Completer<String>();
        final successCheck = expectLater(
          context.guard(success.future),
          throwsA(isA<StaleModuleSessionException>()),
        );
        final failureCheck = expectLater(
          context.guard(failure.future),
          throwsA(isA<StaleModuleSessionException>()),
        );
        context.invalidate();
        success.complete('obsolete');
        failure.completeError(StateError('obsolete error'));
        await Future.wait([successCheck, failureCheck]);
        await expectLater(
          context.guard(Future<String>.error(StateError('already stale'))),
          throwsA(isA<StaleModuleSessionException>()),
        );
        expect(
          () => context.ensureActive(),
          throwsA(isA<StaleModuleSessionException>()),
        );
        expect(
          () => context.onDispose(() {}),
          throwsA(isA<StaleModuleSessionException>()),
        );
        expect(
          const StaleModuleSessionException('alpha', 7).toString(),
          contains('alpha#7'),
        );
      },
    );

    test(
      'cleanup is awaited, LIFO, once, and continues after failure',
      () async {
        final context = ModuleSessionContext(moduleId: 'alpha', generation: 1);
        final calls = <String>[];
        final gate = Completer<void>();
        context.onDispose(() => calls.add('first'));
        context.onDispose(() {
          calls.add('second');
          throw StateError('close failed');
        });
        context.onDispose(() async {
          calls.add('third:start');
          await gate.future;
          calls.add('third:end');
        });
        final disposal = context.disposeAsync();
        final check = expectLater(
          disposal,
          throwsA(
            isA<ModuleDisposalException>().having(
              (error) => error.errors,
              'errors',
              hasLength(1),
            ),
          ),
        );
        expect(context.disposeAsync(), same(disposal));
        expect(calls, ['third:start']);
        expect(context.isActive, isFalse);
        gate.complete();
        await check;
        expect(calls, ['third:start', 'third:end', 'second', 'first']);
        expect(
          ModuleDisposalException([StateError('x')]).toString(),
          contains('1 errors'),
        );
      },
    );
  });

  group('runtime transitions', () {
    test('account change can explicitly restart the same module', () async {
      var closes = 0;
      var account = 'first';
      final runtime = KoiModuleRuntime(
        KoiModuleCatalog([
          module(
            'alpha',
            create: (context) {
              context.onDispose(() => closes++);
              return account;
            },
          ),
        ]),
      );
      final first = await runtime.activate('alpha');
      account = 'second';
      final replacement = await runtime.activate('alpha', restart: true);
      expect(first.capability, 'first');
      expect(first.context.isActive, isFalse);
      expect(replacement.capability, 'second');
      expect(replacement.generation, first.generation + 1);
      expect(closes, 1);
      await runtime.disposeAsync();
      expect(closes, 2);
    });

    test(
      'switch invalidates immediately and awaits cleanup before constructing',
      () async {
        final closeGate = Completer<void>();
        final calls = <String>[];
        final runtime = KoiModuleRuntime(
          KoiModuleCatalog([
            module(
              'alpha',
              create: (context) {
                context.onDispose(() async {
                  calls.add('alpha:closing');
                  await closeGate.future;
                  calls.add('alpha:closed');
                });
                return 'alpha';
              },
            ),
            module(
              'beta',
              create: (_) {
                calls.add('beta:created');
                return 'beta';
              },
            ),
          ]),
        );
        final first = await runtime.activate('alpha');
        expect(await runtime.activate('alpha'), same(first));
        final next = runtime.activate('beta');
        expect(first.context.isActive, isFalse);
        expect(runtime.state.isSwitching, isTrue);
        expect(runtime.state.session, isNull);
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['alpha:closing']);
        closeGate.complete();
        final second = await next;
        expect(calls, ['alpha:closing', 'alpha:closed', 'beta:created']);
        expect(second.moduleId, 'beta');
        expect(second.generation, first.generation + 1);
        final disposal = runtime.disposeAsync();
        expect(runtime.disposeAsync(), same(disposal));
        await disposal;
        expect(second.context.isActive, isFalse);
        expect(runtime.state.session, isNull);
        expect(() => runtime.activate('alpha'), throwsStateError);
      },
    );

    test('unknown module does not invalidate current session', () async {
      final runtime = KoiModuleRuntime(KoiModuleCatalog([module('alpha')]));
      final session = await runtime.activate('alpha');
      expect(() => runtime.activate('unknown'), throwsArgumentError);
      expect(session.context.isActive, isTrue);
      expect(runtime.state.session, same(session));
      await runtime.disposeAsync();
    });

    test('failed creation cleans partial resources and can retry', () async {
      var calls = 0;
      var closes = 0;
      final runtime = KoiModuleRuntime(
        KoiModuleCatalog([
          module(
            'alpha',
            create: (context) {
              context.onDispose(() => closes++);
              if (calls++ == 0) throw StateError('initialization failed');
              return 'ready';
            },
          ),
        ]),
      );
      await expectLater(runtime.activate('alpha'), throwsStateError);
      expect(closes, 1);
      expect(runtime.state.error, isA<StateError>());
      expect(runtime.state.session, isNull);
      expect(runtime.state.isSwitching, isFalse);
      final session = await runtime.activate('alpha');
      expect(session.capability, 'ready');
      expect(runtime.state.error, isNull);
      await runtime.disposeAsync();
      expect(closes, 2);
    });

    test('creation and cleanup errors are both retained', () async {
      final runtime = KoiModuleRuntime(
        KoiModuleCatalog([
          module(
            'alpha',
            create: (context) {
              context.onDispose(() => throw ArgumentError('cleanup'));
              throw StateError('creation');
            },
          ),
        ]),
      );
      await expectLater(
        runtime.activate('alpha'),
        throwsA(
          isA<ModuleDisposalException>().having(
            (error) => error.errors,
            'errors',
            hasLength(2),
          ),
        ),
      );
      await runtime.disposeAsync();
    });

    test(
      'previous cleanup failure stops next factory and remains recoverable',
      () async {
        var betaCreated = false;
        final runtime = KoiModuleRuntime(
          KoiModuleCatalog([
            module(
              'alpha',
              create: (context) {
                context.onDispose(() => throw StateError('cannot close'));
                return 'alpha';
              },
            ),
            module(
              'beta',
              create: (_) {
                betaCreated = true;
                return 'beta';
              },
            ),
          ]),
        );
        await runtime.activate('alpha');
        await expectLater(
          runtime.activate('beta'),
          throwsA(isA<ModuleDisposalException>()),
        );
        expect(betaCreated, isFalse);
        expect(runtime.state.error, isA<ModuleDisposalException>());
        expect(runtime.state.session, isNull);
        await runtime.activate('beta');
        expect(betaCreated, isTrue);
        await runtime.disposeAsync();
      },
    );

    test(
      'rapid selections reject obsolete factories and keep the latest',
      () async {
        final started = Completer<ModuleSessionContext>();
        final finish = Completer<String>();
        final events = <String>[];
        final runtime = KoiModuleRuntime(
          KoiModuleCatalog([
            module(
              'alpha',
              create: (context) {
                context.onDispose(() => events.add('alpha:closed'));
                started.complete(context);
                return finish.future;
              },
            ),
            module(
              'beta',
              create: (_) {
                events.add('beta:created');
                return 'beta';
              },
            ),
          ]),
        );
        final first = runtime.activate('alpha');
        final firstCheck = expectLater(
          first,
          throwsA(isA<StaleModuleSessionException>()),
        );
        final context = await started.future;
        final skipped = runtime.activate('beta');
        final skippedCheck = expectLater(
          skipped,
          throwsA(isA<StaleModuleSessionException>()),
        );
        final latest = runtime.activate('beta');
        expect(context.isActive, isFalse);
        finish.complete('obsolete capability');
        final active = await latest;
        await Future.wait([firstCheck, skippedCheck]);
        expect(active.moduleId, 'beta');
        expect(active.generation, 3);
        expect(events, ['alpha:closed', 'beta:created']);
        expect(runtime.state.error, isNull);
        await runtime.disposeAsync();
      },
    );

    test(
      'dispose during factory rejects completion and closes partial state',
      () async {
        final started = Completer<ModuleSessionContext>();
        final finish = Completer<String>();
        var closes = 0;
        final runtime = KoiModuleRuntime(
          KoiModuleCatalog([
            module(
              'alpha',
              create: (context) {
                context.onDispose(() => closes++);
                started.complete(context);
                return finish.future;
              },
            ),
          ]),
        );
        final activation = expectLater(
          runtime.activate('alpha'),
          throwsA(isA<StaleModuleSessionException>()),
        );
        final context = await started.future;
        final disposal = runtime.disposeAsync();
        expect(context.isActive, isFalse);
        finish.complete('late');
        await activation;
        await disposal;
        expect(closes, 1);
        expect(runtime.state.session, isNull);
      },
    );

    test(
      'ChangeNotifier disposal delegates to asynchronous owned cleanup',
      () async {
        var closed = false;
        final runtime = KoiModuleRuntime(
          KoiModuleCatalog([
            module(
              'alpha',
              create: (context) {
                context.onDispose(() => closed = true);
                return 'alpha';
              },
            ),
          ]),
        );
        await runtime.activate('alpha');
        runtime.dispose();
        await runtime.disposeAsync();
        expect(closed, isTrue);
      },
    );
  });
}
