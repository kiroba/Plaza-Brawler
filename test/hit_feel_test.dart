// Hit-stop / KO slow-mo (lib/game/hit_feel.dart). Pure Dart: runs with plain `dart test` and `flutter test`.
import 'dart:math';

import 'package:plaza_brawler/game/cpu_brain.dart';
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/game/hit_feel.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

HitFx _hit({
  bool blocked = false,
  bool heavy = false,
  bool special = false,
  bool guardBreak = false,
  bool ko = false,
}) => HitFx(
  defender: 1,
  blocked: blocked,
  heavy: heavy,
  special: special,
  guardBreak: guardBreak,
  ko: ko,
);

/// Display steps until the engine is allowed to run again.
int _frozenSteps(HitFeel h) {
  var n = 0;
  while (!h.shouldTick()) {
    n++;
    if (n > 1000) fail('never released');
  }
  return n;
}

/// Same idea as the engine test's scripted player: a new combo every 8 engine frames, from its own Random.
class _Scripted implements InputSource {
  final Random _rng;
  int _bits = 0;
  _Scripted(int seed) : _rng = Random(seed);
  static const _choices = [
    0,
    FighterIntent.left,
    FighterIntent.right,
    FighterIntent.right | FighterIntent.light,
    FighterIntent.light,
    FighterIntent.heavy,
    FighterIntent.block,
    FighterIntent.special,
  ];
  @override
  FighterIntent poll(MatchSnapshot s) {
    if (s.frame % 8 == 0) _bits = _choices[_rng.nextInt(_choices.length)];
    return FighterIntent(
      s.frame.isOdd
          ? _bits &
                ~(FighterIntent.light |
                    FighterIntent.heavy |
                    FighterIntent.special)
          : _bits,
    );
  }
}

FighterDef _f(String sign) => offlineFighter(sign)!;

MatchEngine _engine(int seed, {bool cpuP1 = false}) => MatchEngine(
  p1: _f('aries'),
  p2: _f('leo'),
  input1: cpuP1
      ? CpuInput(
          CpuBrain(def: _f('aries'), difficulty: 0.7, seed: seed ^ 5),
          side: 0,
        )
      : _Scripted(seed),
  input2: CpuInput(
    CpuBrain(def: _f('leo'), difficulty: 0.7, seed: seed),
    side: 1,
  ),
  seed: seed,
);

void main() {
  group('hit-stop lengths', () {
    test('light hit freezes 4 steps, block 2, heavy/special/guard break 8', () {
      final h = HitFeel();
      h.onFx([_hit()]);
      expect(_frozenSteps(h), HitFeel.lightStop);
      expect(HitFeel.lightStop, inInclusiveRange(3, 5));
      h.onFx([_hit(blocked: true)]);
      expect(_frozenSteps(h), HitFeel.blockStop);
      h.onFx([_hit(heavy: true)]);
      expect(_frozenSteps(h), HitFeel.heavyStop);
      h.onFx([_hit(special: true)]);
      expect(_frozenSteps(h), HitFeel.heavyStop);
      h.onFx([_hit(blocked: true, guardBreak: true)]);
      expect(_frozenSteps(h), HitFeel.heavyStop);
      expect(HitFeel.heavyStop, greaterThan(HitFeel.lightStop));
    });

    test('no fx: the engine runs every step', () {
      final h = HitFeel();
      h.onFx(const []);
      for (var i = 0; i < 10; i++) {
        expect(h.shouldTick(), isTrue);
      }
    });

    test('hits during a freeze take the longer stop, they do not stack', () {
      final h = HitFeel();
      h.onFx([_hit(heavy: true)]);
      h.shouldTick();
      h.shouldTick(); // 6 left
      h.onFx([_hit()]); // 4 < 6: unchanged
      expect(h.freezeLeft, HitFeel.heavyStop - 2);
      h.onFx([_hit(heavy: true), _hit(special: true)]);
      expect(h.freezeLeft, HitFeel.heavyStop);
    });
  });

  group('KO slow-mo', () {
    test('KO: freeze, then ~1 s at half speed, banner held until it ends', () {
      final h = HitFeel();
      h.onFx([_hit(heavy: true, ko: true)]);
      expect(h.holdingKo, isTrue);
      // koStop frozen steps, plus the first slow-mo step (half speed: it does not run the engine). The call
      // that ends _frozenSteps is slow-mo step 2, which does run the engine.
      expect(_frozenSteps(h), HitFeel.koStop + 1);
      var ran = 1, steps = 2;
      while (h.slowLeft > 0) {
        if (h.shouldTick()) ran++;
        steps++;
      }
      expect(steps, HitFeel.koSlowSteps);
      expect(ran, HitFeel.koSlowSteps ~/ HitFeel.koSlowEvery);
      expect(
        HitFeel.koSlowSteps,
        inInclusiveRange(50, 70),
      ); // about 1 s at 60 Hz
      expect(h.holdingKo, isFalse);
      expect(h.shouldTick(), isTrue);
    });

    test('reset clears freeze and slow-mo', () {
      final h = HitFeel()..onFx([_hit(ko: true)]);
      h.reset();
      expect(h.holdingKo, isFalse);
      expect(h.shouldTick(), isTrue);
    });
  });

  group('determinism', () {
    for (final (seed, cpuP1) in [
      (1, false),
      (42, false),
      (1, true),
      (9001, true),
    ]) {
      test('gated engine == ungated engine, frame for frame (seed $seed, '
          '${cpuP1 ? 'CPU vs CPU' : 'scripted P1'})', () {
        final plain = _engine(seed, cpuP1: cpuP1);
        final gated = _engine(seed, cpuP1: cpuP1);
        final feel = HitFeel();
        var hits = 0, kos = 0, displaySteps = 0;
        while (!plain.isOver && plain.frame < 60 * 60 * 6) {
          plain.tick();
          // Advance the gated engine through display steps until it has run the same frame.
          while (gated.frame < plain.frame) {
            displaySteps++;
            if (!feel.shouldTick()) continue;
            gated.tick();
            hits += gated.fx.where((f) => !f.blocked).length;
            kos += gated.fx.where((f) => f.ko).length;
            feel.onFx(gated.fx);
          }
          expect(gated.p1.hp, plain.p1.hp);
          expect(gated.p2.hp, plain.p2.hp);
          expect(gated.p1.x, plain.p1.x);
          expect(gated.p2.x, plain.p2.x);
          expect(gated.phase, plain.phase);
        }
        expect(gated.summary(), plain.summary());
        expect(gated.matchWinner, plain.matchWinner);
        expect(hits, greaterThan(0));
        // Freezes added display steps without adding engine frames.
        expect(displaySteps, greaterThan(plain.frame));
        // CPU vs CPU always ends in KOs with these seeds, so the slow-mo path is covered.
        if (cpuP1) expect(kos, greaterThan(0));
        if (kos > 0) {
          expect(
            displaySteps,
            greaterThanOrEqualTo(plain.frame + HitFeel.koStop * kos),
          );
        }
      });
    }
  });
}
