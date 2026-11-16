// Widget smoke tests (flutter test): the title screen shows PLAZA BRAWLER, fits a 360x640 portrait phone
// with no overflow, and its whole icon-grid menu fits an 800x360 landscape phone with no scrolling (the
// old stacked buttons ran off the bottom). (The boot screen isn't pumped here: it starts the periodic
// kiosk timer.)
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
  testWidgets('title menu fits 800x360 landscape on one screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TitleScreen()));
    await tester.pump();
    expect(find.text('PLAY TOGETHER'), findsOneWidget);
    for (final label in [
      'ARCADE',
      'QUICK FIGHT',
      'PLAY TOGETHER',
      'HIGH SCORES',
      'HOW TO PLAY',
      'SETTINGS',
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$label is above the screen');
      expect(
        rect.bottom,
        lessThanOrEqualTo(360),
        reason: '$label is below the screen',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
