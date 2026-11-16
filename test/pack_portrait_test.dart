// Pack sprite rendering (widget): a bound def shows the pack portrait, an
// unbound def the painted portrait, and a binding pointing at a missing
// asset falls back to painted — the pack is an enhancement, never a
// dependency. Also: the arena painter draws a bound fighter's sprite body
// without error.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/art/fighter_painter.dart';
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';

const _realBinding = FighterSpriteBinding(
  portraitAsset:
      'assets/packs/omnimod.base.reference-male-01/sprites/sprite_portrait_128.png',
  bodyAsset:
      'assets/packs/omnimod.base.reference-male-01/sprites/sprite_three_quarter_128.png',
  packId: 'omnimod.base.reference-male-01',
);

const _missingBinding = FighterSpriteBinding(
  portraitAsset: 'assets/packs/omnimod.base.reference-male-01/sprites/nope.png',
  bodyAsset: 'assets/packs/omnimod.base.reference-male-01/sprites/nope.png',
  packId: 'omnimod.base.reference-male-01',
);

Future<void> _letAssetsSettle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('bound def renders the pack portrait image', (tester) async {
    final def = offlineFighter('leo')!.copyWith(sprite: _realBinding);
    await tester.pumpWidget(
      MaterialApp(home: Center(child: FighterPortrait(def: def, size: 132))),
    );
    await _letAssetsSettle(tester);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unbound def renders the painted portrait, no image', (
    tester,
  ) async {
    final def = offlineFighter('leo')!;
    await tester.pumpWidget(
      MaterialApp(home: Center(child: FighterPortrait(def: def, size: 132))),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a binding to a missing asset falls back to painted', (
    tester,
  ) async {
    final def = offlineFighter('leo')!.copyWith(sprite: _missingBinding);
    await tester.pumpWidget(
      MaterialApp(home: Center(child: FighterPortrait(def: def, size: 132))),
    );
    await _letAssetsSettle(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the arena painter draws a bound sprite body', (tester) async {
    ui.Image? img;
    await tester.runAsync(() async {
      img = await loadFighterSpriteImage(_realBinding.bodyAsset);
    });
    expect(img, isNotNull);
    final def = offlineFighter('leo')!.copyWith(sprite: _realBinding);
    final state = FighterState(def, x: 100, facingRight: true);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ArenaPainter.paintFighter(canvas, state, 200, false, sprite: img);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(300, 300);
    expect(rendered.width, 300);
    // And the missing-image path paints the shapes without error.
    final recorder2 = ui.PictureRecorder();
    final canvas2 = Canvas(recorder2);
    ArenaPainter.paintFighter(canvas2, state, 200, true);
    recorder2.endRecording();
  });
}
