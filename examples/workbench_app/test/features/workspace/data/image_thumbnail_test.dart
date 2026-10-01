import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/features/workspace/data/image_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real image decode/resample caps longest edge and preserves aspect ratio',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1024, 512),
        ui.Paint()..color = const ui.Color(0xff0d7755),
      );
      final picture = recorder.endRecording();
      final original = await picture.toImage(1024, 512);
      final bytes = (await original.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      original.dispose();
      picture.dispose();
      final result = await createImageThumbnail(bytes);
      final codec = await ui.instantiateImageCodec(result);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 320);
      expect(image.height, 160);
      image.dispose();
      codec.dispose();
      final small = await createImageThumbnail(result);
      final smallCodec = await ui.instantiateImageCodec(small);
      final smallImage = (await smallCodec.getNextFrame()).image;
      expect(smallImage.width, 320);
      smallImage.dispose();
      smallCodec.dispose();
    },
  );
  test('invalid image bytes fail explicitly', () async {
    await expectLater(
      createImageThumbnail(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<Exception>()),
    );
  });
  test('nonpositive target size is rejected before decode', () async {
    await expectLater(
      createImageThumbnail(Uint8List(0), maxSide: 0),
      throwsArgumentError,
    );
  });
}
