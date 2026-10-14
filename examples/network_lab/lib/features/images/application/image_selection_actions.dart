import 'package:flutter/services.dart';

Future<Uint8List> loadSampleImage() async {
  final data = await rootBundle.load('assets/images/sample.png');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
