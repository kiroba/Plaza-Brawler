// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/main.dart';

void main() {
  testWidgets('Plaza Brawler smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlazaBrawlerApp());

    // Verify boot screen renders title.
    expect(find.text('THE OMNIVERSE'), findsOneWidget);

    // Pump and settle to let boot timer finish
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
