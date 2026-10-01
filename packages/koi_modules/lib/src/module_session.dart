import 'dart:async';

/// A completion belongs to a replaced or disposed module session.
final class StaleModuleSessionException implements Exception {
  const StaleModuleSessionException(this.moduleId, this.generation);

  final String moduleId;
  final int generation;

  @override
  String toString() => 'Stale module session: $moduleId#$generation';
}

/// Every registered cleanup was attempted; these callbacks failed.
final class ModuleDisposalException implements Exception {
  ModuleDisposalException(List<Object> errors)
    : errors = List.unmodifiable(errors);

  final List<Object> errors;

  @override
  String toString() => 'Module cleanup failed (${errors.length} errors).';
}

/// Ownership and cancellation boundary for one module activation.
///
/// Register cancellation/closing before starting asynchronous work. [guard]
/// rejects stale completions; it does not cancel a Future by itself. Cancellation
/// is performed by the callbacks registered with [onDispose].
final class ModuleSessionContext {
  ModuleSessionContext({required this.moduleId, required this.generation});

  final String moduleId;
  final int generation;
  final List<FutureOr<void> Function()> _cleanup = [];
  bool _active = true;
  Future<void>? _disposal;

  bool get isActive => _active;

  void ensureActive() {
    if (!_active) {
      throw StaleModuleSessionException(moduleId, generation);
    }
  }

  void onDispose(FutureOr<void> Function() cleanup) {
    ensureActive();
    _cleanup.add(cleanup);
  }

  Future<T> guard<T>(Future<T> pending) async {
    // Always observe the supplied Future, including if invalidation occurred
    // just before this call. Check ensureActive before starting new work.
    try {
      final value = await pending;
      ensureActive();
      return value;
    } catch (_) {
      ensureActive();
      rethrow;
    }
  }

  /// Immediately invalidates results, even while an earlier cleanup is pending.
  void invalidate() => _active = false;

  /// Closes owned resources once, in reverse registration order.
  Future<void> disposeAsync() {
    invalidate();
    return _disposal ??= _close();
  }

  Future<void> _close() async {
    final errors = <Object>[];
    for (final cleanup in _cleanup.reversed) {
      try {
        await cleanup();
      } catch (error) {
        errors.add(error);
      }
    }
    _cleanup.clear();
    if (errors.isNotEmpty) throw ModuleDisposalException(errors);
  }
}

final class ModuleSession<T extends Object> {
  const ModuleSession({required this.context, required this.capability});

  final ModuleSessionContext context;
  final T capability;

  String get moduleId => context.moduleId;
  int get generation => context.generation;
}
