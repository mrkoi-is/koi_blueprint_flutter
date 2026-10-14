import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/commands/workbench_commands.dart';
import 'package:workbench_app/core/preferences/ui_preferences_store.dart';
import 'package:workbench_app/features/workspace/presentation/providers/appearance_providers.dart';

import 'presentation_support.dart';

void main() {
  testWidgets(
    'commands recheck closing state and propagate durable save failure',
    (tester) async {
      final storage = MemoryStorage();
      final bootstrap = (await tester.runAsync(
        () => WorkbenchBootstrap.create(
          openStorage: () async => storage,
          fileImportPort: CancelImport(),
          createPlayback: FakePlayback.new,
        ),
      ))!;
      final panels = KoiWorkbenchController();
      var exits = 0;
      final commands = WorkbenchCommands(
        bootstrap: bootstrap,
        panels: panels,
        requestExit: () async => exits++,
      );
      bootstrap.session.createDocument(text: 'draft');
      storage.repository.failSave = true;
      expect(
        await tester.runAsync(() => commands.invoke(WorkbenchCommandId.save)),
        isFalse,
      );
      storage.repository.failSave = false;
      expect(
        await tester.runAsync(() => commands.invoke(WorkbenchCommandId.save)),
        isTrue,
      );
      expect(storage.repository.snapshot.documents.single.text, 'draft');
      bootstrap.preparingToClose.value = true;
      for (final id in WorkbenchCommandId.values) {
        expect(commands.enabled(id), isFalse);
        expect(await commands.invoke(id), isFalse);
      }
      expect(exits, 0);
      bootstrap.preparingToClose.value = false;
      expect(await commands.invoke(WorkbenchCommandId.quit), isTrue);
      expect(exits, 1);
      commands.dispose();
      panels.dispose();
      await tester.runAsync(bootstrap.disposeAsync);
    },
  );

  testWidgets(
    'appearance Cancel preserves values; Apply changes locale without replacing session',
    (tester) async {
      final preferences = MemoryUiPreferencesStore();
      final bootstrap = (await tester.runAsync(
        () => WorkbenchBootstrap.create(
          openStorage: () async => MemoryStorage(),
          openPreferences: () async => preferences,
          fileImportPort: CancelImport(),
          createPlayback: FakePlayback.new,
        ),
      ))!;
      final originalSession = bootstrap.session;
      await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
      await tester.pumpAndSettle();
      Future<void> open() async {
        await tester.tap(find.byKey(const ValueKey('workspace-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('语言 / 强调色'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.byKey(const ValueKey('appearance-locale')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        bootstrap.container.read(workbenchAppearanceProvider).value!.locale,
        isNull,
      );
      await open();
      await tester.tap(find.byKey(const ValueKey('appearance-locale')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.text('Documents'), findsWidgets);
      expect(identical(bootstrap.session, originalSession), isTrue);
      expect(
        await bootstrap.container
            .read(workbenchAppearanceProvider.notifier)
            .flush(),
        isTrue,
      );
      expect((await preferences.read())['locale'], 'en');
      await tester.runAsync(bootstrap.disposeAsync);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
