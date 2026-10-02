class WidgetSnapshot {
  const WidgetSnapshot({
    required this.title,
    required this.updatedAt,
    required this.completed,
  });
  final String title;
  final DateTime updatedAt;
  final int completed;
  Map<String, Object?> toJson() => {
    'version': 1,
    'title': title,
    'completed': completed,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  static WidgetSnapshot fromJson(Map<String, Object?> value) {
    if (value['version'] != 1 ||
        value['title'] is! String ||
        value['completed'] is! int ||
        value['updatedAt'] is! String) {
      throw const FormatException('Invalid widget snapshot');
    }
    return WidgetSnapshot(
      title: value['title']! as String,
      completed: value['completed']! as int,
      updatedAt: DateTime.parse(value['updatedAt']! as String),
    );
  }
}

abstract interface class HomeWidgetPort {
  Future<void> publish(WidgetSnapshot snapshot);
}
