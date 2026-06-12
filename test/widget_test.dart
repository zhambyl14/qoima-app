import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qoima/main.dart';

void main() {
  testWidgets('Qoima app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const QoimaApp()); // MyApp → QoimaApp

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
