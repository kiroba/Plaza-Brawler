// Pure-Dart tests for the gamepad mapping (desktop D3): normalized button/axis names in,
// FighterIntent bits out. No plugin, no Flutter — the bridge is a thin forwarder and is not
// tested here; what matters is that the seven existing intents map exactly, taps latch like
// Touch/Keyboard, and nothing else (bumpers, dpadDown, right stick) leaks into an intent.
import 'package:plaza_brawler/game/gamepad_input.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

MatchSnapshot _snap() => MatchEngine(
  p1: offlineFighter('aries')!,
  p2: offlineFighter('scorpio')!,
).snapshot;

void main() {
  group('button mapping (v0)', () {
    final cases = <String, int>{
      'a': FighterIntent.light,
      'b': FighterIntent.heavy,
      'x': FighterIntent.block,
      'y': FighterIntent.special,
      'dpadLeft': FighterIntent.left,
      'dpadRight': FighterIntent.right,
      'dpadUp': FighterIntent.up,
    };
    cases.forEach((name, bit) {
      test('$name -> intent $bit, held until released', () {
        final pad = GamepadInput();
        expect(pad.buttonDown(name), isTrue);
        expect(pad.poll(_snap()).bits, bit);
        expect(pad.poll(_snap()).bits, bit, reason: 'still held');
        expect(pad.buttonUp(name), isTrue);
        expect(pad.poll(_snap()).bits, 0);
      });
    });

    test('unmapped buttons are ignored', () {
      final pad = GamepadInput();
      for (final name in [
        'leftBumper',
        'rightBumper',
        'leftTrigger',
        'rightTrigger',
        'start',
        'back',
        'home',
        'dpadDown',
      ]) {
        expect(pad.buttonDown(name), isFalse, reason: name);
      }
      expect(pad.poll(_snap()).bits, 0);
    });

    test('a tap between ticks is latched, then clears', () {
      final pad = GamepadInput();
      pad.buttonDown('a');
      pad.buttonUp('a');
      expect(pad.poll(_snap()).bits, FighterIntent.light);
      expect(pad.poll(_snap()).bits, 0);
    });

    test('buttons combine', () {
      final pad = GamepadInput();
      pad.buttonDown('dpadRight');
      pad.buttonDown('a');
      expect(
        pad.poll(_snap()).bits,
        FighterIntent.right | FighterIntent.light,
      );
    });
  });

  group('left stick', () {
    test('past the threshold it reads as a held direction', () {
      final pad = GamepadInput();
      pad.axis('leftStickX', -0.8);
      expect(pad.poll(_snap()).bits, FighterIntent.left);
      pad.axis('leftStickX', 0.9);
      expect(pad.poll(_snap()).bits, FighterIntent.right);
      pad.axis('leftStickX', 0.0);
      expect(pad.poll(_snap()).bits, 0);
    });

    test('inside the threshold it reads as nothing', () {
      final pad = GamepadInput();
      pad.axis('leftStickX', 0.49);
      pad.axis('leftStickY', -0.49);
      expect(pad.poll(_snap()).bits, 0);
    });

    test('up is jump; down is nothing (no crouch intent exists)', () {
      final pad = GamepadInput();
      pad.axis('leftStickY', 0.8);
      expect(pad.poll(_snap()).bits, FighterIntent.up);
      pad.axis('leftStickY', -0.8);
      expect(pad.poll(_snap()).bits, 0);
    });

    test('the right stick is ignored', () {
      final pad = GamepadInput();
      pad.axis('rightStickX', 1.0);
      pad.axis('rightStickY', 1.0);
      expect(pad.poll(_snap()).bits, 0);
    });
  });

  test('releaseAll clears buttons, latch and stick', () {
    final pad = GamepadInput();
    pad.buttonDown('b');
    pad.axis('leftStickX', 1.0);
    pad.releaseAll();
    expect(pad.poll(_snap()).bits, 0);
  });
}
