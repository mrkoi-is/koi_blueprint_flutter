import 'dart:typed_data';

import 'package:network_lab/shared/network/domain/http_ports.dart';

sealed class ImageSource {
  const ImageSource();
}

final class AssetImageSource extends ImageSource {
  const AssetImageSource(this.path);
  final String path;
}

final class MemoryImageSource extends ImageSource {
  MemoryImageSource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class LocalImageSource extends ImageSource {
  const LocalImageSource(this.key);
  final String key;
}

final class NetworkImageSource extends ImageSource {
  const NetworkImageSource(this.uri);
  final Uri uri;
}

final class ImagePayload {
  ImagePayload(List<int> bytes, {this.fromCache = false})
    : _bytes = Uint8List.fromList(bytes);
  final Uint8List _bytes;
  final bool fromCache;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

abstract interface class LocalImageReader {
  Future<Uint8List> read(String key, {required int maxBytes});
  Future<String?> pick({required int maxBytes});
  void close();
}

abstract interface class ImageValidator {
  Future<void> validate(Uint8List bytes);
}

abstract interface class ImageRepository {
  Future<ImagePayload> load(
    ImageSource source, {
    required Cancellation cancellation,
  });
  void clear();
  Future<void> close();
}
