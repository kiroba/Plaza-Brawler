// Pure-Dart tests for the on-screen directional stick (Nov 25, 2026 — Kiro's
// v0.3.3 feedback: "needs directional pad instead of seperate buttons. like a
// digital analog stick for movement"): normalized stick offsets in, the SAME
// discrete FighterIntent bits the four arrow buttons used to send out. The
// widget is a thin drag handler over TouchStick.bitsFor + TouchInput, so what
// matters here is the mapping: cardinals, diagonals, the dead zone, clamping,
// and that the bits round-trip through TouchInput the way the widget drives it.
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

MatchSnapshot _snap() => MatchEngine(
  p1: offlineFighter('aries')!,
  p2: offlineFighter('scorpio')!,
).snapshot;

void main() {
  group('TouchStick.bitsFor cardinals', () {
    test('left / right', () {
      expect(TouchStick.bitsFor(-1, 0), FighterIntent.left);
      expect(TouchStick.bitsFor(1, 0), FighterIntent.right);
    });

    test('up is jump; down is crouch', () {
      expect(TouchStick.bitsFor(0, -1), FighterIntent.up);
      expect(TouchStick.bitsFor(0, 1), FighterIntent.crouch);
    });

    test('centre is nothing', () {
      expect(TouchStick.bitsFor(0, 0), 0);
    });
  });

  group('diagonals read as two bits at once', () {
    test('advance + jump', () {
      expect(
        TouchStick.bitsFor(0.8, -0.8),
        FighterIntent.right | FighterIntent.up,
      );
    });

    test('retreat + jump', () {
      expect(
        TouchStick.bitsFor(-0.8, -0.8),
        FighterIntent.left | FighterIntent.up,
      );
    });

    test('advance + crouch', () {
      expect(
        TouchStick.bitsFor(0.8, 0.8),
        FighterIntent.right | FighterIntent.crouch,
      );
    });

    test('retreat + crouch', () {
      expect(
        TouchStick.bitsFor(-0.8, 0.8),
        FighterIntent.left | FighterIntent.crouch,
      );
    });
  });

  group('dead zone', () {
    test('inside it the stick reads as nothing', () {
      expect(TouchStick.bitsFor(0.34, 0), 0);
      expect(TouchStick.bitsFor(0, -0.34), 0);
      expect(TouchStick.bitsFor(0.34, 0.34), 0);
    });

    test('just past it a direction counts', () {
      expect(TouchStick.bitsFor(0.36, 0), FighterIntent.right);
      expect(TouchStick.bitsFor(0, -0.36), FighterIntent.up);
    });

    test('one axis past the dead zone does not drag the other in', () {
      expect(TouchStick.bitsFor(0.9, 0.2), FighterIntent.right);
      expect(TouchStick.bitsFor(0.2, -0.9), FighterIntent.up);
    });
  });

  test('offsets clamp to the stick travel', () {
    expect(TouchStick.bitsFor(2, 0), FighterIntent.right);
    expect(TouchStick.bitsFor(-2, 0), FighterIntent.left);
    expect(TouchStick.bitsFor(0, -2), FighterIntent.up);
    expect(TouchStick.bitsFor(0, 2), FighterIntent.crouch);
  });

  test('opposite directions can never fire together', () {
    final bits = TouchStick.bitsFor(1, 1);
    expect(bits & FighterIntent.left, 0);
    expect(bits & FighterIntent.up, 0);
  });

  group('through TouchInput, as the widget drives it', () {
    test('pressed direction bits poll out, released ones stop', () {
      final touch = TouchInput();
      final bits = TouchStick.bitsFor(-0.8, -0.8);
      for (final flag in TouchStick.directionFlags) {
        if (bits & flag != 0) touch.press(flag);
      }
      expect(touch.poll(_snap()).bits, FighterIntent.left | FighterIntent.up);
      // Thumb slides from up-left to straight left: up releases, left holds.
      touch.release(FighterIntent.up);
      expect(touch.poll(_snap()).bits, FighterIntent.left);
      // Thumb released: everything stops.
      touch.release(FighterIntent.left);
      expect(touch.poll(_snap()).bits, 0);
    });

    test('a tap that crosses the dead zone latches like a button tap', () {
      final touch = TouchInput();
      touch.press(FighterIntent.crouch);
      touch.release(FighterIntent.crouch);
      expect(touch.poll(_snap()).bits, FighterIntent.crouch);
      expect(touch.poll(_snap()).bits, 0);
    });
  });
}
