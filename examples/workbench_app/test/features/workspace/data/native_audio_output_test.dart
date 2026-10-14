import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workbench_app/features/workspace/data/media/native_audio_output_stub.dart';

void main() {
  test('non-native audio override fails before accessing the SDK', () async {
    await expectLater(
      configureNativeAudioOutput(_UnusedPlayer(), 'null'),
      throwsUnsupportedError,
    );
  });
}

// Any unexpected SDK access throws from Fake instead of initializing playback.
final class _UnusedPlayer extends Fake implements Player {}
