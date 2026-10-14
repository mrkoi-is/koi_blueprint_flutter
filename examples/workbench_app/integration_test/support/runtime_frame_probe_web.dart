import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Observes the actual plugin's registered video elements without replacing it.
Map<String, Object?> probeVideoFrame() {
  final instances = globalContext.getProperty<JSAny?>(
    r'$com.alexmercerind.media_kit.instances'.toJS,
  );
  if (instances == null) return const {'elements': <Object?>[]};
  final countValue = globalContext.getProperty<JSAny?>(
    r'$com.alexmercerind.media_kit.instance_count'.toJS,
  );
  final count = int.tryParse(countValue.toString()) ?? 0;
  final elements = <Map<String, Object?>>[];
  for (var index = 0; index < count; index++) {
    final value = (instances as JSObject).getProperty<JSAny?>('$index'.toJS);
    if (value == null || value.isUndefinedOrNull) continue;
    final element = value as web.HTMLVideoElement;
    final record = <String, Object?>{
      'readyState': element.readyState,
      'networkState': element.networkState,
      'currentTime': element.currentTime,
      'paused': element.paused,
      'ended': element.ended,
      'videoWidth': element.videoWidth,
      'videoHeight': element.videoHeight,
      'currentSrc': element.currentSrc,
      'error': element.error?.message,
    };
    if (element.videoWidth > 0 && element.videoHeight > 0) {
      final canvas = web.HTMLCanvasElement()
        ..width = element.videoWidth
        ..height = element.videoHeight;
      try {
        final context =
            canvas.getContext('2d')! as web.CanvasRenderingContext2D;
        context.drawImage(element, 0, 0);
        final pixels = context
            .getImageData(0, 0, element.videoWidth, element.videoHeight)
            .data
            .toDart;
        final colors = <int>{};
        for (var offset = 0; offset < pixels.length; offset += 4) {
          colors.add(
            pixels[offset] << 24 |
                pixels[offset + 1] << 16 |
                pixels[offset + 2] << 8 |
                pixels[offset + 3],
          );
        }
        record['canvas_colors'] = colors.length;
      } catch (error) {
        record['canvas_error'] = error.toString();
      } finally {
        canvas.remove();
      }
    }
    elements.add(record);
  }
  return {'elements': elements};
}
