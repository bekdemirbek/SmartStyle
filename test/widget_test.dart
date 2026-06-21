import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('SmartStyle'),
        ),
      ),
    );

    expect(find.text('SmartStyle'), findsOneWidget);
  });
}
