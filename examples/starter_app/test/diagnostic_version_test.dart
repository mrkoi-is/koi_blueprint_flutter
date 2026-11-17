import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starter_app/core/diagnostics/diagnostic_version.dart';

void main() {
  testWidgets('seven version taps unlock and restart the sequence', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticVersion(version: '1.0+1', onUnlocked: () => opens++),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('1.0+1'));
    }
    expect(opens, 0);
    await tester.tap(find.text('1.0+1'));
    expect(opens, 1);
    await tester.tap(find.text('1.0+1'));
    expect(opens, 1);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DiagnosticVersion(version: 'disabled')),
      ),
    );
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('disabled'));
    }
    expect(opens, 1);
  });
}
