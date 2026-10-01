import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workbench_app/features/workspace/presentation/services/media_frame_gate.dart';

class _BorrowedPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Native frame gate must not mutate or dispose its borrowed player',
  );
}

void main() {
  test(
    'native frame gate borrows the controller readiness future unchanged',
    () async {
      final gate = MediaFrameGate(_BorrowedPlayer());
      final frame = Completer<void>();
      expect(gate.wait(frame.future), same(frame.future));
      await gate.close();
      frame.complete();
      await frame.future;
    },
  );
}
