/// Select the exact reviewed baseline for a macOS product version.
///
/// Other versions must be explicitly reviewed before comparisons are accepted.
String goldenBaselineForMacVersion(String version) {
  final match = RegExp(r'^(\d+)\.\d+(?:\.\d+)?$').firstMatch(version.trim());
  switch (match?.group(1)) {
    case '26':
      return 'baselines/macos-26-arm64';
    case '27':
      return 'baselines/macos-arm64';
    default:
      throw StateError(
        'No reviewed Golden baseline for macOS version: $version',
      );
  }
}
