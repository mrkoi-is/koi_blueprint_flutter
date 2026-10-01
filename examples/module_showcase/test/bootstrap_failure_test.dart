import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/bootstrap.dart';
import 'package:module_showcase/core/services/showcase_services.dart';
import 'package:showcase_alpha/showcase_alpha.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

void main() {
  test(
    'failed bootstrap closes partial session and host infrastructure',
    () async {
      late HostShowcaseServices services;
      await expectLater(
        ShowcaseBootstrap.create(
          buildModules: (shared) {
            services = shared as HostShowcaseServices;
            final alpha = createAlphaModule(shared);
            return [
              KoiModule<ShowcaseRepository>(
                id: alpha.id,
                routes: alpha.routes,
                navigation: alpha.navigation,
                createSession: (context) {
                  context.onDispose(() => shared.record('partial:closed'));
                  throw StateError('initialization failed');
                },
              ),
            ];
          },
        ),
        throwsStateError,
      );
      expect(services.events, ['partial:closed']);
      expect(services.isClosed, isTrue);
    },
  );

  test(
    'showcase validates landing navigation and cleans invalid composition',
    () async {
      late HostShowcaseServices services;
      await expectLater(
        ShowcaseBootstrap.create(
          buildModules: (shared) {
            services = shared as HostShowcaseServices;
            final alpha = createAlphaModule(shared);
            return [
              KoiModule<ShowcaseRepository>(
                id: alpha.id,
                routes: alpha.routes,
                navigation: [],
                createSession: alpha.createSession,
              ),
            ];
          },
        ),
        throwsArgumentError,
      );
      expect(services.isClosed, isTrue);
    },
  );

  test('router construction failure still closes activated session', () async {
    late HostShowcaseServices services;
    await expectLater(
      ShowcaseBootstrap.create(
        buildModules: (shared) {
          services = shared as HostShowcaseServices;
          final alpha = createAlphaModule(shared);
          return [
            KoiModule<ShowcaseRepository>(
              id: alpha.id,
              routes: [
                GoRoute(
                  path: '/alpha',
                  parentNavigatorKey: GlobalKey<NavigatorState>(),
                  builder: (_, _) => const SizedBox(),
                ),
              ],
              navigation: alpha.navigation,
              createSession: alpha.createSession,
            ),
          ];
        },
      ),
      throwsAssertionError,
    );
    expect(services.events, ['alpha:open:1', 'alpha:closed:1']);
    expect(services.isClosed, isTrue);
  });
}
