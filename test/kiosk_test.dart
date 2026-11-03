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
    test('attract loop after 30 s idle on the title; activity resets it', () {
      final c = _Clock(), k = _kiosk(c);
      c.advance(29999);
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

    test('kiosk off -> no actions', () {
      final c = _Clock();
      final k = KioskController(nowMs: c.call);
      c.advance(120000);
      expect(k.evaluate(KioskScreen.title), KioskAction.none);
      expect(k.cornerTap(), isFalse);
    });
  });

  group('hidden exit', () {
    test(
      '5 corner taps within 3 s open the PIN prompt; slower taps do not',
      () {
        final c = _Clock(), k = _kiosk(c);
        for (var i = 0; i < 5; i++) {
          expect(k.cornerTap(), isFalse);
          c.advance(
            800,
          ); // 5 taps span 3.2 s: the first falls out of the window
        }
        expect(k.exitPromptOpen, isFalse);
        c.advance(
          KioskController.exitTapWindowMs + 1,
        ); // let the slow taps expire
        for (var i = 0; i < 4; i++) {
          expect(k.cornerTap(), isFalse);
          c.advance(700);
        }
        expect(k.cornerTap(), isTrue); // 5 taps in 2.8 s
        expect(k.exitPromptOpen, isTrue);
        // Timers are held while the prompt is open.
        c.advance(60000);
        expect(k.evaluate(KioskScreen.title), KioskAction.none);
      },
    );

    test(
      'right PIN leaves kiosk mode; wrong PIN does not; no prompt -> refused',
      () {
        final c = _Clock(), k = _kiosk(c);
        expect(
          k.submitExitPin('2468'),
          isFalse,
          reason: 'needs the taps first',
        );
        for (var i = 0; i < 5; i++) {
          k.cornerTap();
        }
        expect(k.submitExitPin('1111'), isFalse);
        expect(k.enabled, isTrue);
        expect(k.submitExitPin('2468'), isTrue);
        expect(k.enabled, isFalse);
        expect(k.exitPromptOpen, isFalse);
      },
    );

    test('5 wrong PINs lock the prompt for 30 s', () {
      final c = _Clock(), k = _kiosk(c);
      void open() {
        for (var i = 0; i < 5; i++) {
          k.cornerTap();
        }
      }

      open();
      for (var i = 0; i < KioskController.maxPinTries; i++) {
        expect(k.submitExitPin('0000'), isFalse);
      }
      expect(k.pinLockedMs, KioskController.pinCooldownMs);
      open();
      expect(k.submitExitPin('2468'), isFalse, reason: 'locked out');
      expect(k.checkPin('2468'), isFalse);
      c.advance(KioskController.pinCooldownMs);
      expect(k.checkPin('2468'), isTrue);
      expect(k.submitExitPin('2468'), isTrue);
    });
  });

  test('session reset between players: new id and seed, taps and prompt cleared, listeners called', () {
    final c = _Clock(), k = _kiosk(c);
    final s1 = k.session;
    final heard = <int>[];
    k.onSessionReset.add((s) => heard.add(s.id));
    k.cornerTap();
    k.cornerTap();
    c.advance(5000);
    final s2 = k.resetSession();
    expect(s2.id, s1.id + 1);
    expect(s2.startedMs, c.t);
    expect(heard, [s2.id]);
    expect(k.idleMs, 0);
    // The two earlier taps don't count toward the next player's 5.
    for (var i = 0; i < 4; i++) {
      expect(k.cornerTap(), isFalse);
    }
    expect(k.cornerTap(), isTrue);
    final seeds = {s1.runSeed, s2.runSeed, k.resetSession().runSeed};
    expect(seeds.length, 3);
    expect(k.exitPromptOpen, isFalse);
  });
}

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();
