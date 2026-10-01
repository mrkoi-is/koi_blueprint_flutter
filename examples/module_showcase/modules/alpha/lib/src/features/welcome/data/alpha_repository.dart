import 'dart:async';

import 'package:koi_modules/koi_modules.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

/// The module owns its subscription and pending work, never the shared bus.
final class AlphaRepository implements ShowcaseRepository {
  AlphaRepository(this._context, this._services) {
    _subscription = _services.refreshes.listen((_) {
      if (_context.isActive) _services.record('alpha:refresh:$generation');
    });
    _context.onDispose(_close);
    _services.record('alpha:open:$generation');
  }

  final ModuleSessionContext _context;
  final ShowcaseServices _services;
  late final StreamSubscription<void> _subscription;
  final Map<Timer, Completer<String>> _pending = {};

  @override
  String get moduleId => 'alpha';

  @override
  int get generation => _context.generation;

  @override
  Future<String> loadMessage({Duration delay = Duration.zero}) async {
    _context.ensureActive();
    final completer = Completer<String>();
    late final Timer timer;
    timer = Timer(delay, () {
      _pending.remove(timer);
      completer.complete('Alpha capability · session $generation');
    });
    _pending[timer] = completer;
    final message = await _context.guard(completer.future);
    _services.record('alpha:accepted:$generation');
    return message;
  }

  Future<void> _close() async {
    await _subscription.cancel();
    for (final entry in _pending.entries) {
      entry.key.cancel();
      entry.value.completeError(
        StaleModuleSessionException(moduleId, generation),
      );
    }
    _pending.clear();
    _services.record('alpha:closed:$generation');
  }
}
