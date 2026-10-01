@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../features/workspace/data/image_thumbnail_test.dart' as suite;

// Run the same real image decode/resample contract through the Web renderer.
void main() => suite.main();
