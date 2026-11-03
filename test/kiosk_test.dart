// Kiosk (spec 4.7) pure logic: PIN hashing, idle timers, hidden exit, session reset. Fake clock.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:plaza_brawler/game/kiosk.dart';
import 'package:test/test.dart';

class _Clock {
  int t = 1000000;
  int call() => t;
  void advance(int ms) => t += ms;
}

KioskController _kiosk(_Clock c, {String pin = '2468'}) {
  final k = KioskController(nowMs: c.call, random: Random(1));
  expect(k.enable(pin), isTrue);
  return k;
}

void main() {
  group('PIN', () {
    test('4 digits only', () {
      for (final p in ['1234', '0000', '9999']) {
        expect(KioskPin.isValid(p), isTrue, reason: p);
      }
      for (final p in ['123', '12345', 'abcd', '12 4', '', '١٢٣٤']) {
        expect(KioskPin.isValid(p), isFalse, reason: p);
      }
      expect(() => KioskPin.hash('12a4'), throwsArgumentError);
      expect(KioskController().enable('123'), isFalse);
    });

    test('salted sha256; never stored in clear; verifies', () {
      final h = KioskPin.hash('2468', saltHex: '00ff');
      expect(
        h,
        r'00ff$'
        '${_sha('00ff:2468')}',
      );
      expect(h.contains('2468'), isFalse);
      expect(KioskPin.verify('2468', h), isTrue);
      expect(KioskPin.verify('2469', h), isFalse);
      final a = KioskPin.hash('2468'), b = KioskPin.hash('2468');
      expect(a == b, isFalse, reason: 'random salt per hash');
      expect(KioskPin.verify('2468', a) && KioskPin.verify('2468', b), isTrue);
      for (final bad in [null, '', r'$', r'abc$', r'$abc', 'nodollar']) {
        expect(KioskPin.verify('2468', bad), isFalse, reason: '$bad');
      }
    });
  });

  group('idle timers', () {
    test('attract loop after 20 s idle on the title; activity resets it', () {
      final c = _Clock(), k = _kiosk(c);
      expect(KioskController.attractIdleMs, 20000);
      c.advance(19999);
      expect(k.evaluate(KioskScreen.title), KioskAction.none);
      c.advance(1);
      expect(k.evaluate(KioskScreen.title), KioskAction.startAttract);
      k.noteActivity();
      expect(k.evaluate(KioskScreen.title), KioskAction.none);
    });

    test('run end returns to title after 10 s; fight pauses at 45 s, leaves at 60 s', () {
      final c = _Clock(), k = _kiosk(c);
      c.advance(10000);
      expect(k.evaluate(KioskScreen.runEnd), KioskAction.returnToTitle);
      k.noteActivity();
      c.advance(44999);
      expect(k.evaluate(KioskScreen.fight), KioskAction.none);
      c.advance(1);
      expect(k.evaluate(KioskScreen.fight), KioskAction.pauseFight);
      c.advance(15000);
      expect(k.evaluate(KioskScreen.fight), KioskAction.returnToTitle);
      expect(k.evaluate(KioskScreen.attract), KioskAction.none);
      expect(k.evaluate(KioskScreen.other), KioskAction.none);
    });

    test('menus left alone for 45 s go back to the title', () {
      final c = _Clock(), k = _kiosk(c);
      c.advance(KioskController.menuIdleMs - 1);
      expect(k.evaluate(KioskScreen.menu), KioskAction.none);
      c.advance(1);
      expect(k.evaluate(KioskScreen.menu), KioskAction.returnToTitle);
    });

    test('kiosk off -> no actions', () {
      final c = _Clock();
      final k = KioskController(nowMs: c.call);
      c.advance(120000);
      expect(k.evaluate(KioskScreen.title), KioskAction.none);
      k.logoDown();
      c.advance(5000);
      expect(k.logoHeld(), isFalse);
    });
  });

  group('hidden exit', () {
    test('3 s long-press on the logo opens the PIN prompt; shorter or lifted presses do not', () {
      final c = _Clock(), k = _kiosk(c);
      expect(KioskController.exitHoldMs, 3000);
      expect(k.logoHeld(), isFalse, reason: 'never pressed');
      k.logoDown();
      c.advance(2999);
      expect(k.logoHeld(), isFalse);
      k.logoUp();
      c.advance(10);
      expect(k.logoHeld(), isFalse, reason: 'lifted before 3 s');
      expect(k.exitPromptOpen, isFalse);
      k.logoDown();
      c.advance(3000);
      expect(k.logoHeld(), isTrue);
      expect(k.exitPromptOpen, isTrue);
      expect(k.logoHeld(), isFalse, reason: 'one prompt per press');
      // Timers are held while the prompt is open.
      c.advance(60000);
      expect(k.evaluate(KioskScreen.title), KioskAction.none);
      k.cancelExitPrompt();
      expect(k.exitPromptOpen, isFalse);
    });

    test(
      'right PIN leaves kiosk mode; wrong PIN does not; no prompt -> refused',
      () {
        final c = _Clock(), k = _kiosk(c);
        expect(
          k.submitExitPin('2468'),
          isFalse,
          reason: 'needs the long-press first',
        );
        _hold(k, c);
        expect(k.submitExitPin('1111'), isFalse);
        expect(k.enabled, isTrue);
        expect(k.submitExitPin('2468'), isTrue);
        expect(k.enabled, isFalse);
        expect(k.exitPromptOpen, isFalse);
      },
    );

    test('5 wrong PINs lock the prompt for 30 s', () {
      final c = _Clock(), k = _kiosk(c);
      _hold(k, c);
      for (var i = 0; i < KioskController.maxPinTries; i++) {
        expect(k.submitExitPin('0000'), isFalse);
      }
      expect(k.exitPromptOpen, isFalse);
      expect(k.pinLockedMs, KioskController.pinCooldownMs);
      _hold(k, c);
      expect(k.submitExitPin('2468'), isFalse, reason: 'locked out');
      expect(k.checkPin('2468'), isFalse);
      c.advance(KioskController.pinCooldownMs);
      expect(k.checkPin('2468'), isTrue);
      _hold(k, c);
      expect(k.submitExitPin('2468'), isTrue);
    });

    test('4 wrong PINs then the right one: no lockout', () {
      final c = _Clock(), k = _kiosk(c);
      _hold(k, c);
      for (var i = 0; i < KioskController.maxPinTries - 1; i++) {
        expect(k.submitExitPin('0000'), isFalse);
      }
      expect(k.pinLockedMs, 0);
      expect(k.submitExitPin('2468'), isTrue);
    });

    test('disable() turns kiosk off and forgets the PIN', () {
      final c = _Clock(), k = _kiosk(c);
      k.disable();
      expect(k.enabled, isFalse);
      expect(k.pinHash, isNull);
      expect(k.checkPin('2468'), isFalse);
    });
  });

  test('session reset between players: new id and seed, logo hold and prompt cleared, listeners called', () {
    final c = _Clock(), k = _kiosk(c);
    final s1 = k.session;
    final heard = <int>[];
    k.onSessionReset.add((s) => heard.add(s.id));
    k.logoDown();
    c.advance(5000);
    final s2 = k.resetSession();
    expect(s2.id, s1.id + 1);
    expect(s2.startedMs, c.t);
    expect(heard, [s2.id]);
    expect(k.idleMs, 0);
    // The earlier press doesn't carry over to the next player.
    expect(k.logoHeld(), isFalse);
    final seeds = {s1.runSeed, s2.runSeed, k.resetSession().runSeed};
    expect(seeds.length, 3);
    expect(k.exitPromptOpen, isFalse);
  });
}

void _hold(KioskController k, _Clock c) {
  k.logoDown();
  c.advance(KioskController.exitHoldMs);
  expect(k.logoHeld(), isTrue);
}

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();
