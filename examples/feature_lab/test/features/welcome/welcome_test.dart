import 'package:feature_lab/features/welcome/welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders without data dependencies', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));
    expect(find.text('Welcome content'), findsOneWidget);
  });
}
