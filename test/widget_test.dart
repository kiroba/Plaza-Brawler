// Widget smoke test (flutter test): the title screen shows PLAZA BRAWLER and fits a 360x640 phone with no
// overflow. (The boot screen isn't pumped here: it starts the periodic kiosk timer.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/screens/title_screen.dart';

void main() {
  testWidgets('title fits 360x640 with no overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TitleScreen()));
    await tester.pump();
    expect(find.text('PLAZA BRAWLER'), findsOneWidget);
    expect(find.text('ARCADE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
