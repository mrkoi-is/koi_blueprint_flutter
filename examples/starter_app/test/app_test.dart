import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starter_app/app.dart';

void main() {
  testWidgets('opens the initial typed route and disposes router', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StarterApp()));
    await tester.pumpAndSettle();
    expect(find.text('Ready to build'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('about dialog exposes the same build identity as the manifest', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StarterApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: unknown'), findsOneWidget);
    expect(find.textContaining('Channel: local'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
