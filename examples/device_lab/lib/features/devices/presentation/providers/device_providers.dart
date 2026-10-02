import 'dart:async';

import 'package:device_lab/features/devices/application/device_lab_session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'device_providers.g.dart';

@Riverpod(keepAlive: true)
DeviceLabSession deviceSession(Ref ref) =>
    throw UnimplementedError('Bootstrap owns and injects the device session');
@riverpod
Stream<DeviceLabSnapshot> deviceState(Ref ref) {
  final session = ref.watch(deviceSessionProvider);
  final events = StreamController<DeviceLabSnapshot>();
  final subscription = session.changes.listen(
    events.add,
    onError: events.addError,
  );
  events.add(session.state);
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(events.close());
  });
  return events.stream;
}
