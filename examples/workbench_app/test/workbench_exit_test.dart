import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';

import 'presentation_support.dart';

void main() {
  testWidgets('cancellable exit waits for durable save and closes storage', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final bootstrap = (await tester.runAsync(
      () => WorkbenchBootstrap.create(
        openStorage: () async => storage,
        fileImportPort: CancelImport(),
        createPlayback: FakePlayback.new,
      ),
    ))!;
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    bootstrap.session.createDocument(text: '正常退出保存');
    final response = await tester.runAsync(() async {
      final gate = Completer<void>();
      storage.repository.saveGate = gate.future;
      var completed = false;
      final exit = tester.binding.handleRequestAppExit().then((response) {
        completed = true;
        return response;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completed, isFalse);
      expect(storage.closes, 0);
      gate.complete();
      return await exit.timeout(const Duration(seconds: 10));
    });
    expect(response, AppExitResponse.exit);
    expect(storage.repository.snapshot.documents.single.text, '正常退出保存');
    expect(storage.closes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed exit stays usable and a later exit retries saving', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final bootstrap = (await tester.runAsync(
      () => WorkbenchBootstrap.create(
        openStorage: () async => storage,
        fileImportPort: CancelImport(),
        createPlayback: FakePlayback.new,
      ),
    ))!;
    await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    final id = bootstrap.session.createDocument(text: '草稿');
    storage.repository.failSave = true;
    expect(
      await tester.runAsync(tester.binding.handleRequestAppExit),
      AppExitResponse.cancel,
    );
    await tester.pump();
    expect(storage.closes, 0);
    expect(bootstrap.session.state.error, contains('保存失败'));
    bootstrap.session.editDocument(id, '退出失败后仍能编辑');
    storage.repository.failSave = false;
    expect(
      await tester.runAsync(tester.binding.handleRequestAppExit),
      AppExitResponse.exit,
    );
    expect(storage.repository.snapshot.documents.single.text, '退出失败后仍能编辑');
    await tester.pumpWidget(const SizedBox());
  });
}
