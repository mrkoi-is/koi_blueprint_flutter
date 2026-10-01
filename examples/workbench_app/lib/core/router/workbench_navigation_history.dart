import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:workbench_app/features/workspace/application/workspace_session.dart';

typedef WorkbenchPage = ({Uri location, String? resourceId});

/// Session-local page history. Entries identify content, never copy its draft.
final class WorkbenchNavigationHistory extends ChangeNotifier {
  WorkbenchNavigationHistory({
    required this.router,
    required this.workspace,
    this.maxEntries = 100,
  }) : assert(maxEntries >= 2) {
    router.routeInformationProvider.addListener(_observe);
    _subscription = workspace.changes.listen((_) => _observe());
    _observe();
  }

  final GoRouter router;
  final WorkspaceSession workspace;
  final int maxEntries;
  final _entries = <WorkbenchPage>[];
  late final StreamSubscription<Object?> _subscription;
  int _index = -1;
  bool _restoring = false;
  bool _closed = false;
  Object? _lastNotification;
  Future<void>? _closing;

  WorkbenchPage? get current => _index < 0 ? null : _entries[_index];
  bool get canGoBack => _findAvailable(-1) != null;
  bool get canGoForward => _findAvailable(1) != null;

  WorkbenchPage? _capture() {
    final location = router.routeInformationProvider.value.uri;
    final snapshot = workspace.state.snapshot;
    final preferences = snapshot.preferences;
    final resourceId = switch (location.path) {
      '/text' =>
        snapshot.documents
                .where((item) => item.id == preferences.selectedDocumentId)
                .firstOrNull
                ?.id ??
            snapshot.documents.firstOrNull?.id,
      '/media' =>
        snapshot.assets
            .where((item) => item.id == preferences.selectedAssetId)
            .firstOrNull
            ?.id,
      '/tasks' => null,
      _ => null,
    };
    if (!['/text', '/media', '/tasks'].contains(location.path)) return null;
    return (location: location, resourceId: resourceId);
  }

  bool _available(WorkbenchPage page) {
    final id = page.resourceId;
    if (id == null) return true;
    final snapshot = workspace.state.snapshot;
    return switch (page.location.path) {
      '/text' => snapshot.documents.any((item) => item.id == id),
      '/media' => snapshot.assets.any((item) => item.id == id),
      _ => true,
    };
  }

  int? _findAvailable(int direction) {
    if (_closed) return null;
    for (
      var index = _index + direction;
      index >= 0 && index < _entries.length;
      index += direction
    ) {
      if (_entries[index] != current && _available(_entries[index])) {
        return index;
      }
    }
    return null;
  }

  void _observe() {
    if (_closed || _restoring) return;
    final page = _capture();
    if (page == null) return;
    if (page != current) {
      _entries.removeRange(_index + 1, _entries.length);
      _entries.add(page);
      if (_entries.length > maxEntries) _entries.removeAt(0);
      _index = _entries.length - 1;
    }
    _notifyIfChanged();
  }

  void _notifyIfChanged() {
    final state = (current, _index, canGoBack, canGoForward);
    if (state == _lastNotification) return;
    _lastNotification = state;
    notifyListeners();
  }

  void goBack() => _move(-1);
  void goForward() => _move(1);

  void _move(int direction) {
    _observe();
    final index = _findAvailable(direction);
    if (index == null) return;
    final page = _entries[index];
    final preferences = workspace.state.snapshot.preferences;
    _restoring = true;
    try {
      workspace.updatePreferences(switch (page.location.path) {
        '/text' => preferences.copyWith(
          navId: 'text',
          selectedDocumentId: page.resourceId,
        ),
        '/media' => preferences.copyWith(
          navId: 'media',
          selectedAssetId: page.resourceId,
        ),
        _ => preferences.copyWith(navId: 'tasks'),
      });
      // Replay a captured URI; ordinary new navigation keeps typed routes.
      router.go(page.location.toString());
      _index = index;
      // An earlier empty page may now contain newly imported content.
      _entries[index] = _capture() ?? page;
    } finally {
      _restoring = false;
    }
    _notifyIfChanged();
  }

  Future<void> disposeAsync() {
    dispose();
    return _closing!;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    router.routeInformationProvider.removeListener(_observe);
    _closing = _subscription.cancel();
    super.dispose();
  }
}
