import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A decoded and resampled image, rather than a renamed source image.
Future<Uint8List> createImageThumbnail(
  Uint8List bytes, {
  int maxSide = 320,
}) async {
  if (maxSide <= 0) throw ArgumentError.value(maxSide, 'maxSide');
  if (kIsWeb) return _createWebThumbnail(bytes, maxSide);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final ratio = math.min(
      1.0,
      maxSide / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * ratio).round()),
      targetHeight: math.max(1, (descriptor.height * ratio).round()),
    );
    image = (await codec.getNextFrame()).image;
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) throw StateError('无法编码图片缩略图');
    return encoded.buffer.asUint8List();
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> _createWebThumbnail(Uint8List bytes, int maxSide) async {
  // Encoded ImageDescriptor.width/height are unsupported by Flutter Web.
  // Decode a frame to get real dimensions, then paint a bounded output image.
  final codec = await ui.instantiateImageCodec(bytes);
  ui.Image? source;
  ui.Picture? picture;
  ui.Image? thumbnail;
  try {
    source = (await codec.getNextFrame()).image;
    final ratio = math.min(
      1.0,
      maxSide / math.max(source.width, source.height),
    );
    final width = math.max(1, (source.width * ratio).round());
    final height = math.max(1, (source.height * ratio).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    picture = recorder.endRecording();
    thumbnail = await picture.toImage(width, height);
    final encoded = await thumbnail.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) throw StateError('无法编码浏览器图片缩略图');
    return encoded.buffer.asUint8List();
  } finally {
    thumbnail?.dispose();
    picture?.dispose();
    source?.dispose();
    codec.dispose();
  }
}
