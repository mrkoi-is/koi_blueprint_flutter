import 'package:media_kit/media_kit.dart';

/// The SDK's Web stub intentionally omits NativePlayer.setProperty.
Future<void> configureNativeAudioOutput(Player player, String output) async {
  final platform = player.platform;
  if (platform is! NativePlayer) {
    throw UnsupportedError('Native audio output requires a native player');
  }
  await platform.setProperty('ao', output);
}
