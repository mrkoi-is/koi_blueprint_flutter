abstract interface class UiPreferencesStore {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> values);
  Future<void> close();
}

class MemoryUiPreferencesStore implements UiPreferencesStore {
  Map<String, Object?> _values = {};
  @override
  Future<Map<String, Object?>> read() async => Map.of(_values);
  @override
  Future<void> write(Map<String, Object?> values) async {
    _values = Map.of(values);
  }

  @override
  Future<void> close() async {}
}

/// Optional settings initialize persistence before ProviderScope is created.
abstract final class UiPreferencesRuntime {
  static const managedByBootstrap = false;
  static UiPreferencesStore store = MemoryUiPreferencesStore();
  static Future<bool> Function()? flush;
}
