/// Shared business capability. Modules never depend on the host or each other.
abstract interface class ShowcaseRepository {
  String get moduleId;
  int get generation;
  Future<String> loadMessage({Duration delay = Duration.zero});
}

/// Infrastructure supplied and owned by the host.
abstract interface class ShowcaseServices {
  Stream<void> get refreshes;
  void record(String event);
}
