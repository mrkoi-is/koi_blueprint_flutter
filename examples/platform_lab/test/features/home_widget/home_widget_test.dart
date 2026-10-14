import 'package:platform_lab/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_ui/koi_ui.dart';
import 'package:platform_lab/features/home_widget/domain/widget_snapshot.dart';
import 'package:platform_lab/features/home_widget/presentation/home_widget_page.dart';
import 'package:platform_lab/features/home_widget/presentation/providers/home_widget_providers.dart';

class _WidgetPort implements HomeWidgetPort {
  int calls = 0;
  WidgetSnapshot? snapshot;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> publish(WidgetSnapshot value) async {
    calls++;
    snapshot = value;
    await pending?.future;
    if (fail) throw StateError('native update failed');
  }
}

void main() {
  test('home widget snapshot is versioned and strict', () {
    final snapshot = WidgetSnapshot(
      title: 'Drafts',
      completed: 4,
      updatedAt: DateTime.utc(2026, 10, 2),
    );
    expect(
      WidgetSnapshot.fromJson(snapshot.toJson()).toJson(),
      snapshot.toJson(),
    );
    expect(
      () => WidgetSnapshot.fromJson({'version': 2}),
      throwsFormatException,
    );
  });
  testWidgets(
    'home widget publishes once, reports failures and confirms retry',
    (tester) async {
      final port = _WidgetPort()
        ..pending = Completer<void>()
        ..fail = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeWidgetPortProvider.overrideWithValue(port)],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              KoiUiLocalizations.delegate,
              ...AppLocalizations.localizationsDelegates,
            ],
            theme: AppTheme.light,
            home: const HomeWidgetPage(),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Pending drafts');
      await tester.tap(find.byTooltip('Increment completed count'));
      await tester.tap(find.text('Update home widget'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(port.calls, 1);
      expect(port.snapshot!.completed, 1);
      expect(port.snapshot!.title, 'Pending drafts');
      port.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('native update failed'), findsOneWidget);
      port.fail = false;
      port.pending = null;
      await tester.tap(find.text('Update home widget'));
      await tester.pumpAndSettle();
      expect(port.calls, 2);
      expect(find.text('Snapshot sent to the native widget.'), findsOneWidget);
    },
  );
}
