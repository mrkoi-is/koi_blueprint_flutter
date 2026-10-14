import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:koi_core/koi_core.dart';
import 'package:koi_modules/src/module_session.dart';

/// Navigation data supplied by a module's public, typed route entry point.
final class ModuleNavigationItem {
  const ModuleNavigationItem({
    required this.id,
    required this.label,
    required this.location,
  });

  final String id;
  final String label;
  final String location;
}

/// A compile-time contribution. The factory owns only its session resources.
final class KoiModule<T extends Object> {
  KoiModule({
    required this.id,
    required List<RouteBase> routes,
    required List<ModuleNavigationItem> navigation,
    required this.createSession,
    Set<String> capabilities = const {},
    this.checkAvailability,
  }) : capabilities = Set.unmodifiable(capabilities),
       routes = List.unmodifiable(routes),
       navigation = List.unmodifiable(navigation);

  final String id;

  /// Stable operation identifiers supported by this compiled implementation.
  final Set<String> capabilities;

  /// Rechecked before each new session; absence preserves existing behavior.
  final FutureOr<CapabilityAvailability> Function()? checkAvailability;
  final List<RouteBase> routes;
  final List<ModuleNavigationItem> navigation;
  final FutureOr<T> Function(ModuleSessionContext context) createSession;
}

/// Immutable module composition. There is deliberately no global registry.
final class KoiModuleCatalog<T extends Object> {
  KoiModuleCatalog(List<KoiModule<T>> modules)
    : modules = List.unmodifiable(modules) {
    final ids = <String>{};
    final paths = <String>{};
    final names = <String>{};
    final navigationIds = <String>{};
    for (final module in modules) {
      if (module.id.isEmpty || !ids.add(module.id)) {
        throw ArgumentError('Empty or duplicate module id: ${module.id}');
      }
      if (module.capabilities.any(
        (id) => !RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(id),
      )) {
        throw ArgumentError('Invalid capability identifier in ${module.id}');
      }
      _validateRoutes(module.routes, '', paths, names);
      for (final item in module.navigation) {
        if (item.id.isEmpty || !navigationIds.add(item.id)) {
          throw ArgumentError('Empty or duplicate navigation id: ${item.id}');
        }
        if (!item.location.startsWith('/')) {
          throw ArgumentError('Navigation location must be absolute.');
        }
      }
    }
  }

  final List<KoiModule<T>> modules;

  List<RouteBase> get routes =>
      List.unmodifiable([for (final module in modules) ...module.routes]);

  KoiModule<T> module(String id) => modules.firstWhere(
    (module) => module.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown module'),
  );

  static void _validateRoutes(
    List<RouteBase> routes,
    String parent,
    Set<String> paths,
    Set<String> names,
  ) {
    for (final route in routes) {
      var prefix = parent;
      if (route is GoRoute) {
        prefix = route.path.startsWith('/')
            ? route.path
            : '$parent/${route.path}';
        if (!paths.add(prefix)) {
          throw ArgumentError('Duplicate module route: $prefix');
        }
        final name = route.name;
        if (name != null && !names.add(name)) {
          throw ArgumentError('Duplicate module route name: $name');
        }
      }
      _validateRoutes(route.routes, prefix, paths, names);
    }
  }
}
