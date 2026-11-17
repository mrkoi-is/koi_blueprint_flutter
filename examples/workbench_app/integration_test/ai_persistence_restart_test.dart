import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/data/workspace_storage.dart';

const _id = String.fromEnvironment('KOI_TEST_STORAGE_ID');
const _phase = String.fromEnvironment('KOI_TEST_PERSISTENCE_PHASE');
const _text = '跨进程保存：Workbench 真实草稿';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('persistent text survives a separate application process', (
    tester,
  ) async {
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(_id), isTrue);
    expect(['write', 'read'], contains(_phase));
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/koi_restart_test_$_id');
    if (_phase == 'write') {
      expect(await directory.exists(), isFalse);
      await directory.create(recursive: true);
    } else {
      expect(await directory.exists(), isTrue);
    }
    WorkbenchBootstrap? bootstrap;
    var completed = false;
    try {
      bootstrap = await WorkbenchBootstrap.create(
        openStorage: () =>
            openWorkspaceStorage(nativeDirectory: directory.path),
        initialLocation: '/text',
      );
      await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
      await tester.pumpAndSettle();
      if (_phase == 'write') {
        expect(bootstrap.session.state.snapshot.documents, isEmpty);
        await tester.tap(find.byKey(const ValueKey('new-document')));
        await tester.pumpAndSettle();
        final document = bootstrap.session.state.snapshot.documents.single;
        await tester.enterText(
          find.byKey(ValueKey('editor-${document.id}')),
          _text,
        );
        await tester.pump();
        final modifier = Platform.isMacOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modifier);
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (bootstrap.session.state.snapshot.documents.single.dirty ||
            bootstrap.session.state.saving) {
          if (DateTime.now().isAfter(deadline)) {
            fail('UI save did not finish: ${bootstrap.session.state.error}');
          }
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(bootstrap.session.state.error, isNull);
      } else {
        final document = bootstrap.session.state.snapshot.documents.single;
        final field = tester.widget<TextField>(
          find.byKey(ValueKey('editor-${document.id}')),
        );
        expect(field.controller!.text, _text);
        expect(document.dirty, isFalse);
      }
      final prepared = await bootstrap.prepareToClose();
      expect(prepared.succeeded, isTrue);
      completed = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap?.disposeAsync();
      if ((_phase == 'read' || !completed) && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
