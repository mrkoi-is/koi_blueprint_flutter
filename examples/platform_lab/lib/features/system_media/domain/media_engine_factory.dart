import 'package:koi_core/koi_core.dart';
import 'package:platform_lab/features/system_media/domain/media_engine.dart';

/// Availability checks actual initialization, not only the operating-system name.
abstract interface class MediaEngineFactory {
  String get id;
  Future<CapabilityAvailability> probe();
  Future<MediaEngine> create();
}
