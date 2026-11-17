import 'package:flutter_test/flutter_test.dart';

import 'golden_environment.dart';

void main() {
  test('selects the reviewed macOS baseline by product version', () {
    expect(goldenBaselineForMacVersion('26.7.2'), 'baselines/macos-26-arm64');
    expect(goldenBaselineForMacVersion('27.0.1\n'), 'baselines/macos-arm64');
  });

  test('rejects unknown or malformed macOS versions', () {
    for (final version in ['25.0', '28.0', '26', '26.7.2beta', '']) {
      expect(() => goldenBaselineForMacVersion(version), throwsStateError);
    }
  });
}
