import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/core/providers/module_providers.dart';
import 'package:module_showcase/core/services/showcase_services.dart';
import 'package:module_showcase/shared/showcase_shell.dart';
import 'package:showcase_alpha/showcase_alpha.dart' as alpha;
import 'package:showcase_beta/showcase_beta.dart' as beta;
import 'package:showcase_contracts/showcase_contracts.dart';

/// Owns infrastructure, the root provider container and one stable router.
final class ShowcaseBootstrap {
  ShowcaseBootstrap._(this.services, this.runtime, this.container, this.router);

  final HostShowcaseServices services;
  final KoiModuleRuntime<ShowcaseRepository> runtime;
  final ProviderContainer container;
  final GoRouter router;
  Future<void>? _disposal;

  static Future<ShowcaseBootstrap> create({
    String initialLocation = '/alpha',
    List<KoiModule<ShowcaseRepository>> Function(ShowcaseServices services)?
    buildModules,
  }) async {
    final services = HostShowcaseServices();
    KoiModuleRuntime<ShowcaseRepository>? ownedRuntime;
    ProviderContainer? ownedContainer;
    GoRouter? ownedRouter;
    try {
      final catalog = KoiModuleCatalog(
        buildModules?.call(services) ??
            [
              alpha.createAlphaModule(services),
              beta.createBetaModule(
                services,
                checkAvailability: () => services.betaAvailability,
              ),
            ],
      );
      // The reusable catalog permits route-only modules. This example's picker
      // needs a landing destination for every selectable module.
      if (catalog.modules.isEmpty ||
          catalog.modules.any((module) => module.navigation.isEmpty)) {
        throw ArgumentError(
          'The showcase requires a navigation entry per module.',
        );
      }
      final runtime = KoiModuleRuntime(catalog);
      ownedRuntime = runtime;
      final initialPath = Uri.parse(initialLocation).path;
      final initialModule = catalog.modules.firstWhere(
        (module) => _containsLocation(module, initialPath),
        orElse: () => catalog.modules.first,
      );
      // Direct detail routes receive their session without visiting a home page.
      await runtime.activate(initialModule.id);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          moduleRuntimeProvider.overrideWithValue(runtime),
          showcaseServicesProvider.overrideWithValue(services),
          activeShowcaseRepositoryProvider.overrideWith((ref) {
            final session = ref.watch(moduleSnapshotProvider).session;
            if (session == null) {
              throw StateError('Module session is switching.');
            }
            return session.capability;
          }),
        ],
      );
      ownedContainer = container;
      final router = GoRouter(
        initialLocation: initialLocation,
        refreshListenable: runtime,
        redirect: (context, state) {
          final snapshot = runtime.state;
          final session = snapshot.session;
          if (session == null) {
            return state.uri.path == '/switching' ? null : '/switching';
          }
          final module = catalog.module(session.moduleId);
          if (state.uri.path == '/switching' || state.uri.path == '/') {
            return module.navigation.first.location;
          }
          final belongsToInactiveModule = catalog.modules.any(
            (candidate) =>
                candidate.id != module.id &&
                _containsLocation(candidate, state.uri.path),
          );
          return belongsToInactiveModule
              ? module.navigation.first.location
              : null;
        },
        routes: [
          ShellRoute(
            builder: (context, state, child) => ShowcaseShell(child: child),
            routes: [
              GoRoute(
                path: '/switching',
                builder: (_, _) => const Center(child: Text('等待模块会话就绪')),
              ),
              ...catalog.routes,
            ],
          ),
        ],
      );
      ownedRouter = router;
      return ShowcaseBootstrap._(services, runtime, container, router);
    } catch (error, stackTrace) {
      final failures = <Object>[error];
      for (final cleanup in <FutureOr<void> Function()>[
        if (ownedRouter != null) ownedRouter.dispose,
        if (ownedContainer != null) ownedContainer.dispose,
        if (ownedRuntime != null) ownedRuntime.disposeAsync,
        services.close,
      ]) {
        try {
          await cleanup();
        } catch (cleanupError) {
          failures.add(cleanupError);
        }
      }
      Error.throwWithStackTrace(
        failures.length == 1 ? error : ModuleDisposalException(failures),
        stackTrace,
      );
    }
  }

  static bool _containsLocation(
    KoiModule<ShowcaseRepository> module,
    String location,
  ) => module.navigation.any(
    (entry) =>
        location == entry.location || location.startsWith('${entry.location}/'),
  );

  Future<void> disposeAsync() => _disposal ??= _close();

  Future<void> _close() async {
    router.dispose();
    container.dispose();
    try {
      await runtime.disposeAsync();
    } finally {
      await services.close();
    }
  }
}
