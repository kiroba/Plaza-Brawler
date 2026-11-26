// Fighter select fits the screen (Nov 26, 2026 — Kiro's phone proof: on
// CHOOSE YOUR FIGHTER the dossier and the CHOOSE button sat below the fold
// on a landscape phone): on a short (landscape) screen the carousel sits
// beside the dossier + button, so the whole screen fits at rest; the page
// stays scrollable for anything still taller. The tall (portrait) layout
// is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/app_state.dart';
import 'package:plaza_brawler/screens/character_select_screen.dart';

/// Pumps the select screen on a surface of [size] logical pixels.
Future<void> _pumpSelect(
  WidgetTester tester,
  Size size, {
  required String preselected,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CharacterSelectScreen(
        title: 'CHOOSE YOUR FIGHTER',
        preselected: preselected,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('fighter select fits a short screen', () {
    testWidgets('unlocked fighter: dossier + CHOOSE button inside 800x360',
        (tester) async {
      appState.bossBeaten = false;
      addTearDown(() => appState.bossBeaten = false);
      await _pumpSelect(
        tester,
        const Size(800, 360),
        preselected: 'aries',
      );
      expect(tester.takeException(), isNull);
      // The whole screen fits at rest: the CHOOSE button's bottom edge is
      // inside the viewport, no scrolling needed to reach it.
      final buttonRect = tester.getRect(find.byType(FilledButton));
      expect(buttonRect.top, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(360));
      // Side by side, not stacked: the button sits right of the carousel.
      final carouselRect = tester.getRect(find.byType(PageView));
      expect(buttonRect.left, greaterThan(carouselRect.right));
      expect(buttonRect.top, lessThan(carouselRect.bottom));
      // The swipe hint is dropped on a short screen; the peeking
      // neighbours carry the affordance.
      expect(find.textContaining('SWIPE'), findsNothing);
    });

    testWidgets('locked secret slot: ??? dossier + button inside 800x360',
        (tester) async {
      appState.bossBeaten = false;
      addTearDown(() => appState.bossBeaten = false);
      await _pumpSelect(
        tester,
        const Size(800, 360),
        preselected: 'creepyman',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('???'), findsOneWidget);
      final buttonRect = tester.getRect(find.byType(FilledButton));
      expect(buttonRect.top, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(360));
    });

    testWidgets('tall screen keeps the stacked layout', (tester) async {
      appState.bossBeaten = false;
      addTearDown(() => appState.bossBeaten = false);
      await _pumpSelect(
        tester,
        const Size(360, 800),
        preselected: 'aries',
      );
      expect(tester.takeException(), isNull);
      // The swipe hint is back, and the button sits below the carousel.
      expect(find.textContaining('SWIPE'), findsOneWidget);
      final buttonRect = tester.getRect(find.byType(FilledButton));
      final carouselRect = tester.getRect(find.byType(PageView));
      expect(buttonRect.top, greaterThan(carouselRect.bottom));
      expect(buttonRect.bottom, lessThanOrEqualTo(800));
    });
  });
}
