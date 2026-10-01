import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:koi_modules/src/module_catalog.dart';
import 'package:koi_modules/src/module_session.dart';

@immutable
final class ModuleRuntimeState<T extends Object> {
  const ModuleRuntimeState({
    this.session,
    this.requestedModuleId,
    this.isSwitching = false,
    this.error,
  });

  final ModuleSession<T>? session;
  final String? requestedModuleId;
  final bool isSwitching;
  final Object? error;
}

/// Serializes lifecycle transitions while immediately invalidating old results.
///
/// The host constructs the catalog and owns shared infrastructure. Only module
/// factories register session cleanup. The host must await [disposeAsync] before
/// closing shared infrastructure. Router configuration need not be replaced.
final class KoiModuleRuntime<T extends Object> extends ChangeNotifier {
  KoiModuleRuntime(this.catalog);

  final KoiModuleCatalog<T> catalog;
  ModuleRuntimeState<T> _state = const ModuleRuntimeState();
  ModuleSessionContext? _creating;
  ModuleSession<T>? _ownedSession;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  int _generation = 0;
  bool _closed = false;

  ModuleRuntimeState<T> get state => _state;

  /// Reuses the active session unless [restart] is true. The host must restart
  /// when an account or tenant boundary changes, even if the module id is equal.
  Future<ModuleSession<T>> activate(String moduleId, {bool restart = false}) {
    if (_closed) throw StateError('Module runtime is disposed.');
    final module = catalog.module(moduleId);
    final active = _state.session;
    if (!restart &&
        !_state.isSwitching &&
        active != null &&
        active.moduleId == moduleId) {
      return Future.value(active);
    }
    final generation = ++_generation;
    _ownedSession?.context.invalidate();
    _creating?.invalidate();
    _publish(
      ModuleRuntimeState(requestedModuleId: moduleId, isSwitching: true),
    );
    final result = _tail.then((_) => _activate(module, generation));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ModuleSession<T>> _activate(
    KoiModule<T> module,
    int generation,
  ) async {
    ModuleSessionContext? context;
    try {
      _ensureCurrent(module.id, generation);
      final previous = _ownedSession;
      _ownedSession = null;
      await previous?.context.disposeAsync();
      _ensureCurrent(module.id, generation);
      context = ModuleSessionContext(
        moduleId: module.id,
        generation: generation,
      );
      _creating = context;
      final capability = await module.createSession(context);
      _ensureCurrent(module.id, generation);
      context.ensureActive();
      final session = ModuleSession(context: context, capability: capability);
      _ownedSession = session;
      _creating = null;
      _publish(
        ModuleRuntimeState(session: session, requestedModuleId: module.id),
      );
      return session;
    } catch (error, stackTrace) {
      Object failure = error;
      try {
        await context?.disposeAsync();
      } catch (cleanupError) {
        failure = ModuleDisposalException([error, cleanupError]);
      }
      if (identical(_creating, context)) _creating = null;
      if (!_closed && generation == _generation) {
        _publish(
          ModuleRuntimeState(requestedModuleId: module.id, error: failure),
        );
      }
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  void _ensureCurrent(String moduleId, int generation) {
    if (_closed || generation != _generation) {
      throw StaleModuleSessionException(moduleId, generation);
    }
  }

  void _publish(ModuleRuntimeState<T> next) {
    _state = next;
    notifyListeners();
  }

  Future<void> disposeAsync() {
    if (_disposal != null) return _disposal!;
    _closed = true;
    _generation++;
    _ownedSession?.context.invalidate();
    _creating?.invalidate();
    return _disposal = _disposeOwned();
  }

  Future<void> _disposeOwned() async {
    await _tail;
    final previous = _ownedSession;
    _ownedSession = null;
    try {
      await previous?.context.disposeAsync();
    } finally {
      _state = const ModuleRuntimeState();
      super.dispose();
    }
  }

  /// Prefer awaiting [disposeAsync] in the host's asynchronous shutdown.
  /// The superclass is disposed once, in [_disposeOwned]'s finally block.
  @override
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
