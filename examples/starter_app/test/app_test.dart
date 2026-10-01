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
}
