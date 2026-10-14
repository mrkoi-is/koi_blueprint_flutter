import 'dart:typed_data';

/// A native texture may be registered before its first decodable frame exists.
/// Retry empty snapshots briefly, while the preview owner remains alive.
Future<Uint8List?> captureVideoFrame(
  Future<Uint8List?> Function() capture, {
  required bool Function() isActive,
  int attempts = 20,
  Duration retryDelay = const Duration(milliseconds: 50),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!isActive()) return null;
    final bytes = await capture();
    if (!isActive()) return null;
    if (bytes != null && bytes.isNotEmpty) return bytes;
    if (attempt + 1 < attempts) await Future<void>.delayed(retryDelay);
  }
  return null;
}
