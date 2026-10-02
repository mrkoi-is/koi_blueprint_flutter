import 'dart:async';

import 'package:network_lab/features/network/domain/network_models.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'network_providers.g.dart';

@Riverpod(keepAlive: true)
NetworkSessionPort networkSession(Ref ref) =>
    throw UnimplementedError('Override networkSessionProvider at bootstrap');
@riverpod
Stream<NetworkSnapshot> networkSnapshot(Ref ref) {
  final session = ref.watch(networkSessionProvider);
  return Stream.multi((controller) {
    final subscription = session.changes.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.addSync(session.snapshot);
    controller.onCancel = subscription.cancel;
  });
}
