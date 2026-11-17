// Slice S3 (Nov 16, 2026): combos — the counter, string cancels, the named
// finishers (One-Two, Plaza Finisher), the Elemental Finish, and CPU strings.
//
// Frame script used by the string tests (LP = 3/2/8, hitstun 8):
//   t0 LP press -> LP1 starts; t3 LP1 hits (combo 1)
//   t2 LP press (buffered) -> chain restarts LP at t5; t8 LP2 hits (combo 2)
//   t7 finisher press (buffered) -> string cancel at t10 (LP2's first
//   recovery frame); the finisher connects while the defender is still
//   reeling (combo 3) — the Plaza HK lands on the very tick the stun would
//   expire, which still counts: the defender never got an actionable frame.
import 'package:plaza_brawler/game/cpu_brain.dart';
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/game/moves.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

const _none = FighterIntent.none;
const _lp = FighterIntent(FighterIntent.lp);
const _hp = FighterIntent(FighterIntent.hp);
const _hk = FighterIntent(FighterIntent.hk);
const _special = FighterIntent(FighterIntent.special);

FighterDef _f(String sign) => offlineFighter(sign)!;

/// A match already past its round intro, with the fighters placed at [x1] and [x2].
MatchEngine _fight(String s1, String s2, {double x1 = 200, double x2 = 248}) {
  final e = MatchEngine(p1: _f(s1), p2: _f(s2));
  for (var i = 0; i < MatchEngine.introFrames; i++) {
    e.tickWith(_none, _none);
  }
  expect(e.phase, MatchPhase.fight);
  e.p1.x = x1;
  e.p2.x = x2;
  return e;
}

int _dmg(FighterDef d, int base) => (base * d.stats.damageMultiplier).round();

/// Steps [ticks] ticks, feeding P1 the intents in [script] (tick -> intent,
/// default none) and P2 nothing. Returns every finisher mark P1 carried.
Set<String> _script(MatchEngine e, Map<int, FighterIntent> script, int ticks) {
  final marks = <String>{};
  for (var t = 0; t < ticks; t++) {
    e.tickWith(script[t] ?? _none, _none);
    marks.add(e.p1.finisher);
  }
  return marks;
}

void main() {
  group('combos (S3)', () {
    test('LP-LP-HK is the Plaza Finisher: 3-hit combo, buffed HK, +100 banked', () {
      final e = _fight('aries', 'taurus');
      final hp0 = e.p2.hp;
      final marks = _script(e, {0: _lp, 2: _lp, 7: _hk}, 45);
      expect(marks, contains('plaza'));
      expect(e.p1.bestCombo, 3);
      expect(
        e.p2.hp,
        hp0 -
            _dmg(e.p1.def, Moves.lp.damage) -
            _dmg(e.p1.def, Moves.lp.damage) -
            _dmg(e.p1.def, Moves.hkPlaza.damage),
      );
      // Combo over (defender recovered): +50 per hit past the first.
      expect(e.p1.combo, 0);
      expect(e.p1.comboScore, 100);
    });

    test('LP-LP-HP is the One-Two: the HP carries +3 base damage', () {
      final e = _fight('aries', 'taurus');
      final hp0 = e.p2.hp;
      final marks = _script(e, {0: _lp, 2: _lp, 7: _hp}, 45);
      expect(marks, contains('one_two'));
      expect(e.p1.bestCombo, 3);
      expect(
        e.p2.hp,
        hp0 -
            _dmg(e.p1.def, Moves.lp.damage) -
            _dmg(e.p1.def, Moves.lp.damage) -
            _dmg(e.p1.def, Moves.hpOneTwo.damage),
      );
      expect(e.p1.comboScore, 100);
    });

    test('a two-hit combo banks +50 and the counter clears on recovery', () {
      final e = _fight('aries', 'taurus');
      _script(e, {0: _lp, 2: _lp}, 40);
      expect(e.p1.bestCombo, 2);
      expect(e.p1.comboScore, 50);
      expect(e.p1.combo, 0);
    });

    test('a single hit is not a combo and banks nothing', () {
      final e = _fight('aries', 'taurus');
      _script(e, {0: _lp}, 40);
      expect(e.p1.bestCombo, 1);
      expect(e.p1.comboScore, 0);
    });

    test('HK after one LP is a plain HK — no finisher without the string', () {
      final e = _fight('aries', 'taurus');
      final hp0 = e.p2.hp;
      final marks = _script(e, {0: _lp, 2: _hk}, 45);
      expect(marks, isNot(contains('plaza')));
      expect(e.p1.bestCombo, 1); // the HK lands after the stun expired
      expect(
        e.p2.hp,
        hp0 - _dmg(e.p1.def, Moves.lp.damage) - _dmg(e.p1.def, Moves.hk.damage),
      );
    });

    test('special cancelled at combo 3+ is an Elemental Finish', () {
      final e = _fight('aries', 'taurus');
      e.p1.meter = Moves.meterMax;
      var sawElementalMark = false;
      var sawElementalFx = false;
      final script = {0: _lp, 2: _lp, 7: _hp, 15: _special};
      for (var t = 0; t < 60; t++) {
        e.tickWith(script[t] ?? _none, _none);
        if (e.p1.finisher == 'elemental') sawElementalMark = true;
        for (final fx in e.fx) {
          if (fx.special && fx.elementalFinish && fx.defender == 1) {
            sawElementalFx = true;
          }
        }
      }
      expect(e.p1.bestCombo, greaterThanOrEqualTo(3));
      expect(sawElementalMark, isTrue);
      expect(sawElementalFx, isTrue);
    });

    test('a throw ends a running combo and banks its bonus', () {
      final e = _fight('aries', 'taurus');
      // A live combo state, with the defender back on their feet in grab
      // range (the frame-perfect case: the throw was started while the
      // defender was still reeling and connects on their recovery tick).
      e.p1.combo = 2;
      e.p1.comboLpTail = 2;
      e.tickWith(const FighterIntent(FighterIntent.throwBtn), _none);
      for (var i = 0; i < 10; i++) {
        e.tickWith(_none, _none);
      }
      expect(e.p1.combo, 0);
      expect(e.p1.comboScore, 50);
    });

    test('deterministic: same string inputs, same hash', () {
      String play() {
        final e = _fight('aries', 'taurus');
        _script(e, {0: _lp, 2: _lp, 7: _hk}, 45);
        return e.stateHash();
      }

      expect(play(), play());
    });
  });

  group('cpu strings (S3)', () {
    // P2 (the CPU) is mid-string: LP in recovery, two LPs connected, the
    // opponent reeling. decide() should reach for a finisher button with a
    // frequency that follows the ruled chance 0.1 + Wit*0.05 + difficulty*0.3.
    int finisherPresses({required int wit, required double difficulty}) {
      var count = 0;
      for (var seed = 0; seed < 40; seed++) {
        final def = _f('taurus').copyWith(
          stats: FighterStats(power: 5, agility: 5, wit: wit, resolve: 5),
        );
        final e = MatchEngine(p1: _f('aries'), p2: def);
        for (var i = 0; i < MatchEngine.introFrames; i++) {
          e.tickWith(_none, _none);
        }
        e.p1.x = 200;
        e.p2.x = 320; // out of plan range, so only the follow-through can press
        e.p1.action = FighterAction.hitstun;
        e.p1.stunFrames = 12;
        e.p2.action = FighterAction.lp;
        e.p2.actionFrames = 6; // LP recovery
        e.p2.combo = 2;
        e.p2.comboLpTail = 2;
        final brain = CpuBrain(def: def, difficulty: difficulty, seed: seed);
        final intent = brain.decide(e.snapshot, 1);
        if (intent.has(FighterIntent.hk) || intent.has(FighterIntent.hp)) {
          count++;
        }
      }
      return count;
    }

    test('high Wit + max difficulty finishes most strings', () {
      expect(finisherPresses(wit: 10, difficulty: 1.0), greaterThanOrEqualTo(28));
    });

    test('low Wit + zero difficulty rarely finishes', () {
      expect(finisherPresses(wit: 1, difficulty: 0.0), lessThanOrEqualTo(12));
    });
  });
}
