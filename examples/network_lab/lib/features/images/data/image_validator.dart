import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:network_lab/features/images/domain/image_source.dart';

/// Bounded headers work on Web too, where ImageDescriptor dimensions are absent.
/// The engine still decodes the bytes before they can enter the cache.
({int width, int height}) imageDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  bool tag(int offset, List<int> value) =>
      bytes.length >= offset + value.length &&
      List.generate(
        value.length,
        (i) => bytes[offset + i] == value[i],
      ).every((v) => v);
  if (bytes.length >= 24 &&
      tag(0, [137, 80, 78, 71, 13, 10, 26, 10]) &&
      tag(12, [73, 72, 68, 82])) {
    return (width: data.getUint32(16), height: data.getUint32(20));
  }
  if (bytes.length >= 10 &&
      (tag(0, [71, 73, 70, 56, 55, 97]) || tag(0, [71, 73, 70, 56, 57, 97]))) {
    return (
      width: data.getUint16(6, Endian.little),
      height: data.getUint16(8, Endian.little),
    );
  }
  if (bytes.length >= 30 &&
      tag(0, [82, 73, 70, 70]) &&
      tag(8, [87, 69, 66, 80])) {
    if (tag(12, [86, 80, 56, 88])) {
      return (
        width: 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16),
        height: 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16),
      );
    }
    if (tag(12, [86, 80, 56, 76]) && bytes[20] == 47) {
      return (
        width: 1 + ((bytes[21] | bytes[22] << 8) & 0x3fff),
        height:
            1 + ((bytes[22] >> 6) | bytes[23] << 2 | (bytes[24] & 15) << 10),
      );
    }
    if (tag(12, [86, 80, 56, 32]) && tag(23, [157, 1, 42])) {
      return (
        width: data.getUint16(26, Endian.little) & 0x3fff,
        height: data.getUint16(28, Endian.little) & 0x3fff,
      );
    }
  }
  if (tag(0, [255, 216])) {
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset++] != 255) break;
      while (offset < bytes.length && bytes[offset] == 255) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 217 || marker == 218) break;
      if (marker == 1 || (marker >= 208 && marker <= 216)) continue;
      if (offset + 2 > bytes.length) break;
      final length = data.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) break;
      if ({
            192,
            193,
            194,
            195,
            197,
            198,
            199,
            201,
            202,
            203,
            205,
            206,
            207,
          }.contains(marker) &&
          length >= 7) {
        return (
          width: data.getUint16(offset + 5),
          height: data.getUint16(offset + 3),
        );
      }
      offset += length;
    }
  }
  throw FormatException(
    'Unsupported or truncated image; use PNG, JPEG, GIF or WebP',
  );
}

final class FlutterImageValidator implements ImageValidator {
  const FlutterImageValidator({this.maxPixels = 16 * 1024 * 1024});
  final int maxPixels;
  @override
  Future<void> validate(Uint8List bytes) async {
    final size = imageDimensions(bytes);
    if (size.width < 1 ||
        size.height < 1 ||
        size.width * size.height > maxPixels) {
      throw StateError('Image pixel budget exceeded');
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1,
      targetHeight: 1,
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }
}
