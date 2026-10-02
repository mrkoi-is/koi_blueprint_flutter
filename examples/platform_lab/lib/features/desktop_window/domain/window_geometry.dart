import 'dart:math' as math;

/// Coordinates are logical pixels, matching the window and screen plugins.
class WindowGeometry {
  const WindowGeometry({required this.bounds, this.maximized = false});
  final WindowBounds bounds;
  final bool maximized;

  static WindowGeometry? fromJson(Object? value) {
    if (value is! Map) return null;
    final numbers = [value['x'], value['y'], value['width'], value['height']];
    if (numbers.any((v) => v is! num || !v.isFinite)) return null;
    final [x, y, width, height] = numbers.cast<num>();
    if (width < 100 || height < 100 || width > 20000 || height > 20000) {
      return null;
    }
    return WindowGeometry(
      bounds: WindowBounds.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
      maximized: value['maximized'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
    'maximized': maximized,
  };

  /// Recover unplugged-monitor positions and fit the current visible desktop.
  WindowGeometry fitTo(List<WindowBounds> workAreas) {
    final areas = workAreas
        .where((area) => area.isFinite && area.width > 0 && area.height > 0)
        .toList();
    if (areas.isEmpty) {
      return const WindowGeometry(
        bounds: WindowBounds.fromLTWH(40, 40, 1000, 700),
      );
    }
    final screen = areas.firstWhere(
      (area) => area.overlaps(bounds),
      orElse: () => areas.first,
    );
    final width = math.min(math.max(320.0, bounds.width), screen.width);
    final height = math.min(math.max(240.0, bounds.height), screen.height);
    final x = bounds.left.clamp(screen.left, screen.right - width).toDouble();
    final y = bounds.top.clamp(screen.top, screen.bottom - height).toDouble();
    return WindowGeometry(
      bounds: WindowBounds.fromLTWH(x, y, width, height),
      maximized: maximized,
    );
  }
}

class WindowBounds {
  const WindowBounds.fromLTWH(this.left, this.top, this.width, this.height);
  final double left, top, width, height;
  double get right => left + width;
  double get bottom => top + height;
  bool get isFinite =>
      [left, top, width, height].every((value) => value.isFinite);
  bool overlaps(WindowBounds other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;
}
