import 'dart:async';

import 'package:device_lab/features/local_setup/application/local_setup_session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'local_setup_providers.g.dart';

@Riverpod(keepAlive: true)
LocalSetupSession localSetupSession(Ref ref) =>
    throw UnimplementedError('Composition owns local setup');
@riverpod
Stream<int> localSetupChanges(Ref ref) {
  final session = ref.watch(localSetupSessionProvider);
  final controller = StreamController<int>();
  final sub = session.changes.listen(
    controller.add,
    onError: controller.addError,
  );
  controller.add(0);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
}
