@TestOn('vm')
library;

import 'dart:io';

import 'package:database_lab/capabilities/database_capability.dart';
import 'package:database_lab/core/database/open_database_native.dart';
import 'package:database_lab/features/library/application/library_session.dart';
import 'package:database_lab/features/library/presentation/providers/library_providers.dart';
import 'package:database_lab/features/library/presentation/screens/library_page.dart';
import 'package:database_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_core/koi_core.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'Owned database operation must complete');
}

void main() {
  testWidgets(
    'embedded database retries opening, persists, and closes with host',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('library-owner-'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      var deny = true;
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getApplicationSupportDirectory');
            requests++;
            if (deny) {
              throw PlatformException(
                code: 'directory-denied',
                message: 'fixture directory denied',
              );
            }
            return directory.path;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await CapabilityLifecycle.instance.close();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(builder: buildDatabaseLabCapability),
        ),
      );
      await _until(tester, () => find.text('Retry').evaluate().isNotEmpty);
      expect(find.textContaining('fixture directory denied'), findsOneWidget);
      expect(requests, 1);
      deny = false;
      await tester.tap(find.text('Retry'));
      await _until(
        tester,
        () => find.byType(LibraryPage).evaluate().isNotEmpty,
      );
      expect(requests, 2);
      final repository = ProviderScope.containerOf(
        tester.element(find.byType(LibraryPage)),
      ).read(libraryRepositoryProvider);
      final prepared = await tester.runAsync(
        CapabilityLifecycle.instance.prepare,
      );
      expect(prepared, isTrue);
      // Preparation does not close the owner; a cancelled host exit can keep
      // using this very repository. The SQLite connection is real here.
      await tester.runAsync(
        () => repository.save(
          title: 'Survives close',
          body: 'saved by embedded capability',
          tags: ['persistent'],
        ),
      );
      await _until(
        tester,
        () => find.text('Survives close').evaluate().isNotEmpty,
      );
      await tester.runAsync(CapabilityLifecycle.instance.close);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        final session = LibrarySession(
          openNativeDatabase(File('${directory.path}/koi_library.sqlite')),
        );
        try {
          await session.initialize();
          final note = (await session.repository.watch().first).single;
          expect(note.title, 'Survives close');
          expect(note.body, 'saved by embedded capability');
          expect(note.tags, ['persistent']);
        } finally {
          final firstClose = session.close();
          expect(identical(firstClose, session.close()), isTrue);
          await firstClose;
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
