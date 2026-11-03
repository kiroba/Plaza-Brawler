// Pure-Dart tests for the Plaza Brawler fight engine, CPU and arcade ladder (spec 4.3 - 4.5).
// No Flutter imports, so they run with plain `dart test` in a harness as well as with `flutter test`.
import 'dart:math';

import 'package:plaza_brawler/game/arcade.dart';
import 'package:plaza_brawler/game/cpu_brain.dart';
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/game/moves.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

const _none = FighterIntent.none;

/// Scripted P1: a new random button/direction combo every 8 frames, from its own seeded Random.
class ScriptedInput implements InputSource {
  final Random _rng;
  int _bits = 0;
  ScriptedInput(int seed) : _rng = Random(seed);

  static const _choices = [
    0,
    FighterIntent.left,
    FighterIntent.right,
    FighterIntent.right | FighterIntent.light,
    FighterIntent.light,
    FighterIntent.heavy,
    FighterIntent.block,
    FighterIntent.up | FighterIntent.right,
    FighterIntent.special,
  ];

  @override
  FighterIntent poll(MatchSnapshot s) {
    if (s.frame % 8 == 0) _bits = _choices[_rng.nextInt(_choices.length)];
    // Release on odd frames so presses register as rising edges.
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

/// A match already past its round intro, with the fighters placed at [x1] and [x2].
MatchEngine _fight(String s1, String s2, {double x1 = 200, double x2 = 260}) {
  final e = MatchEngine(p1: _f(s1), p2: _f(s2));
  for (var i = 0; i < MatchEngine.introFrames; i++) {
    e.tickWith(_none, _none);
  }
  expect(e.phase, MatchPhase.fight);
  e.p1.x = x1;
  e.p2.x = x2;
  return e;
}

void _run(
  MatchEngine e,
  int n, [
  FighterIntent a = _none,
  FighterIntent b = _none,
]) {
  for (var i = 0; i < n; i++) {
    e.tickWith(a, b);
  }
}

int _dmg(FighterDef d, int base) => (base * d.stats.damageMultiplier).round();

String _playOut(int seed) {
  final e = MatchEngine(
    p1: _f('aries'),
    p2: _f('scorpio'),
    seed: seed,
    input1: ScriptedInput(seed),
    input2: CpuInput(CpuBrain(def: _f('scorpio'), difficulty: 0.6, seed: seed)),
  );
  for (var i = 0; i < 3600; i++) {
    e.tick();
  }
  return '${e.stateHash()}|${e.p1.hitsLanded}|${e.p2.hitsLanded}';
}

String _cpuVsCpu(int seed) {
  final e = MatchEngine(
    p1: bossFighter(),
    p2: _f('gemini'),
    seed: seed,
    input1: CpuInput(
      CpuBrain(def: bossFighter(), difficulty: 1.0, seed: seed),
      side: 0,
    ),
    input2: CpuInput(
      CpuBrain(def: _f('gemini'), difficulty: 0.3, seed: seed + 1),
    ),
  );
  for (var i = 0; i < 3600; i++) {
    e.tick();
  }
  return e.stateHash();
}

void main() {
  group('determinism', () {
    test(
      'same seed + scripted inputs -> same stateHash after 3,600 ticks, twice',
      () {
        final a = _playOut(1234);
        final b = _playOut(1234);
        expect(a, b);
        final parts = a.split('|');
        expect(
          int.parse(parts[1]) + int.parse(parts[2]),
          greaterThan(0),
          reason: 'the fight should have hits in it',
        );
        expect(
          _playOut(99),
          isNot(a),
          reason: 'a different seed should play out differently',
        );
      },
    );

    test('CPU vs CPU (boss with all four specials) replays identically', () {
      expect(_cpuVsCpu(7), _cpuVsCpu(7));
    });

    test('stateHash is a sha256 hex string', () {
      final e = MatchEngine(p1: _f('leo'), p2: _f('virgo'));
      expect(e.stateHash(), matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('hits', () {
    test('one light attack lands exactly once (multi-hit fix)', () {
      final e = _fight('aries', 'taurus');
      final hp0 = e.p2.hp;
      e.tickWith(const FighterIntent(FighterIntent.light), _none);
      _run(e, 30);
      expect(e.p1.hitsLanded, 1);
      expect(e.p2.hp, hp0 - _dmg(e.p1.def, Moves.light.damage));
      expect(e.p1.meter, Moves.meterOnHit);
    });

    test('holding light through all active frames still hits once', () {
      final e = _fight('aries', 'taurus');
      final hp0 = e.p2.hp;
      _run(e, Moves.light.total - 1, const FighterIntent(FighterIntent.light));
      _run(e, 20);
      expect(e.p1.hitsLanded, 1);
      expect(e.p2.hp, hp0 - _dmg(e.p1.def, Moves.light.damage));
    });

    test('a hit causes hitstun of active + 6 frames', () {
      final e = _fight('aries', 'taurus');
      e.tickWith(const FighterIntent(FighterIntent.light), _none);
      var guard = 0;
      while (e.p1.hitsLanded == 0 && guard++ < 20) {
        e.tickWith(_none, _none);
      }
      expect(e.p2.action, FighterAction.hitstun);
      expect(e.p2.stunFrames, Moves.light.hitstun);
      expect(Moves.light.hitstun, Moves.light.active + 6);
    });

    test('Flare Rush lands 3 hits of 8 and costs a full meter', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 330);
      e.p1.meter = Moves.meterMax;
      final hp0 = e.p2.hp;
      e.tickWith(const FighterIntent(FighterIntent.special), _none);
      _run(e, 60);
      expect(e.p1.specialsUsed, 1);
      expect(e.p1.hitsLanded, 3);
      expect(e.p2.hp, hp0 - 3 * _dmg(e.p1.def, 8));
      expect(e.p1.meter, 3 * Moves.meterOnHit);
    });

    test('Flare Rush lands all 3 hits wherever in its dash it connects', () {
      for (var d = 45.0; d <= 200; d += 5) {
        final e = _fight('aries', 'taurus', x1: 150, x2: 150 + d);
        e.p1.meter = Moves.meterMax;
        e.tickWith(const FighterIntent(FighterIntent.special), _none);
        _run(e, 60);
        expect(e.p1.hitsLanded, 3, reason: 'start distance $d');
      }
    });

    test('a special needs a full meter', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 330);
      e.p1.meter = Moves.meterMax - 1;
      e.tickWith(const FighterIntent(FighterIntent.special), _none);
      _run(e, 60);
      expect(e.p1.specialsUsed, 0);
      expect(e.p1.hitsLanded, 0);
    });
  });

  group('block', () {
    test('blocked hit deals 20% chip and +4 meter', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 250);
      const block = FighterIntent(FighterIntent.block);
      _run(e, 4, _none, block);
      final hp0 = e.p2.hp;
      e.tickWith(const FighterIntent(FighterIntent.light), block);
      _run(e, 20, _none, block);
      expect(e.p1.hitsBlocked, 1);
      expect(e.p1.hitsLanded, 0);
      expect(
        e.p2.hp,
        hp0 -
            max(
              1,
              (_dmg(e.p1.def, Moves.light.damage) * Moves.chipFraction).round(),
            ),
      );
      expect(e.p1.meter, Moves.meterOnBlock);
    });

    test('3 blocked hits within 60 frames -> guard break, 40-frame stun', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 250);
      const block = FighterIntent(FighterIntent.block);
      _run(e, 4, _none, block);
      final start = e.frame;
      var broke = -1;
      for (var i = 0; i < 60 && broke < 0; i++) {
        // Tap light every other tick so the chain keeps going (rising edges).
        e.tickWith(FighterIntent(i.isEven ? FighterIntent.light : 0), block);
        if (e.p1.guardBreaks > 0) broke = e.frame;
      }
      expect(broke, greaterThan(0), reason: 'guard should break');
      expect(broke - start, lessThan(Moves.guardBreakWindow));
      expect(e.p1.hitsBlocked, 3);
      expect(e.p2.action, FighterAction.hitstun);
      expect(e.p2.stunFrames, Moves.guardBreakStun);
      expect(e.p2.blocking, isFalse);
      // Stays stunned (even holding block) for exactly 40 frames.
      _run(e, Moves.guardBreakStun - 1, _none, block);
      expect(e.p2.action, FighterAction.hitstun);
      e.tickWith(_none, block);
      expect(e.p2.action, isNot(FighterAction.hitstun));
    });

    test('blocked hits spread wider than 60 frames do not break the guard', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 250);
      const block = FighterIntent(FighterIntent.block);
      _run(e, 4, _none, block);
      for (var n = 0; n < 3; n++) {
        e.p1.x = e.p2.x - 50;
        e.tickWith(const FighterIntent(FighterIntent.light), block);
        _run(e, 40, _none, block);
      }
      expect(e.p1.hitsBlocked, 3);
      expect(e.p1.guardBreaks, 0);
      expect(e.p2.action, FighterAction.block);
    });
  });

  group('rounds', () {
    test('round ends on the timer and the higher HP% wins', () {
      final e = _fight('aries', 'taurus');
      e.tickWith(const FighterIntent(FighterIntent.light), _none);
      var guard = 0;
      while (e.phase == MatchPhase.fight &&
          guard++ < MatchEngine.roundFrames + 10) {
        e.tickWith(_none, _none);
      }
      expect(e.phase, MatchPhase.roundOver);
      expect(e.roundFramesLeft, 0);
      final r = e.results.single;
      expect(r.ko, isFalse);
      expect(r.timeout, isTrue);
      expect(r.winner, 0);
      expect(e.wins, [1, 0]);
      final ev = e.drainEvents().map((x) => x.type).toList();
      expect(ev, ['FIGHTER_MATCH_START', 'FIGHTER_ROUND_END']);
    });

    test('timeout compares HP percentage, not raw HP', () {
      // Taurus max 108, Gemini max 96: 60/108 = 55.6% loses to 55/96 = 57.3%.
      final e = _fight('taurus', 'gemini', x1: 100, x2: 500);
      e.p1.hp = 60;
      e.p2.hp = 55;
      _run(e, MatchEngine.roundFrames);
      expect(e.phase, MatchPhase.roundOver);
      expect(e.results.single.winner, 1);
      expect(e.results.single.ko, isFalse);
    });

    test('best of 3: two round wins end the match with a summary', () {
      final e = _fight('aries', 'taurus', x1: 100, x2: 500);
      e.p2.hp = 1;
      _run(e, MatchEngine.roundFrames + MatchEngine.roundOverFrames);
      expect(e.round, 2);
      _run(e, MatchEngine.introFrames);
      e.p2.hp = 1;
      _run(e, MatchEngine.roundFrames + MatchEngine.roundOverFrames);
      expect(e.isOver, isTrue);
      expect(e.matchWinner, 0);
      final end = e.drainEvents().last;
      expect(end.type, 'FIGHTER_MATCH_END');
      expect(end.payload['winner'], 'p1');
      expect(e.drainEvents().where((x) => x.type == 'FIGHTER_HIT'), isEmpty);
    });
  });

  group('arcade ladder', () {
    test('11 signs excluding the player, then Ophiuchus; same order for the same seed', () {
      for (final player in zodiacSigns) {
        final l = ArcadeRun.buildLadder(42, player);
        expect(l.length, 12);
        expect(l.last, 'ophiuchus');
        final rest = l.sublist(0, 11);
        expect(rest, isNot(contains(player)));
        expect(rest.toSet(), zodiacSigns.where((s) => s != player).toSet());
        expect(ArcadeRun.buildLadder(42, player), l);
      }
      final run = ArcadeRun(seed: 5, player: _f('leo'));
      expect(run.ladder, ArcadeRun(seed: 5, player: _f('leo')).ladder);
      expect(run.ladder, isNot(ArcadeRun(seed: 6, player: _f('leo')).ladder));
      expect(run.offlineOpponent().sign, run.ladder.first);
    });

    test('difficulty 0.15 -> 0.85 across the ladder, boss 1.0', () {
      expect(ArcadeRun.difficultyAt(0, 12), closeTo(0.15, 1e-9));
      expect(ArcadeRun.difficultyAt(10, 12), closeTo(0.85, 1e-9));
      expect(ArcadeRun.difficultyAt(11, 12), 1.0);
      for (var i = 1; i < 11; i++) {
        expect(
          ArcadeRun.difficultyAt(i, 12),
          greaterThan(ArcadeRun.difficultyAt(i - 1, 12)),
        );
      }
    });
  });

  group('scoring (spec 4.5)', () {
    RoundResult r({
      int? winner = 0,
      bool ko = true,
      int hp = 50,
      int maxHp = 102,
      int secs = 30,
    }) => RoundResult(
      round: 1,
      winner: winner,
      ko: ko,
      winnerHp: hp,
      winnerMaxHp: maxHp,
      framesLeft: secs * 60,
    );

    test('KO 1,000 + HP x10 + time left x20', () {
      // 1000 + 50*10 + 30*20 = 2100
      expect(ArcadeScoring.round(r(), playerSide: 0), 2100);
    });

    test('perfect round adds 500', () {
      // 1000 + 102*10 + 45*20 + 500 = 3420
      expect(ArcadeScoring.round(r(hp: 102, secs: 45), playerSide: 0), 3420);
    });

    test('timeout win has no KO bonus; lost and drawn rounds score 0', () {
      expect(
        ArcadeScoring.round(r(ko: false, hp: 40, secs: 0), playerSide: 0),
        400,
      );
      expect(ArcadeScoring.round(r(winner: 1), playerSide: 0), 0);
      expect(ArcadeScoring.round(r(winner: null, ko: false), playerSide: 0), 0);
    });

    test('beating the boss adds 2,000; a loss drops that fight\'s points; 3 continues', () {
      final run = ArcadeRun(seed: 1, player: _f('aries'));
      expect(run.continuesLeft, 3);
      run.onRound(r());
      expect(run.liveScore, 2100);
      expect(run.onFightEnd(playerWon: true), RunStatus.fighting);
      expect(run.score, 2100);
      expect(run.index, 1);

      run.onRound(r());
      expect(run.onFightEnd(playerWon: false), RunStatus.lostAwaitingContinue);
      expect(run.score, 2100);
      expect(run.useContinue(), isTrue);
      expect(run.continuesLeft, 2);

      run.index = run.length - 1; // jump to the boss
      expect(run.atBoss, isTrue);
      expect(run.offlineOpponent().isBoss, isTrue);
      run.onRound(r(hp: 102, secs: 45));
      expect(run.onFightEnd(playerWon: true), RunStatus.won);
      expect(run.score, 2100 + 3420 + 2000);
      expect(run.finished, isTrue);
    });

    test('no continues left ends the run', () {
      final run = ArcadeRun(seed: 1, player: _f('aries'));
      for (var i = 0; i < 3; i++) {
        run.onFightEnd(playerWon: false);
        expect(run.useContinue(), isTrue);
      }
      expect(run.onFightEnd(playerWon: false), RunStatus.over);
      expect(run.useContinue(), isFalse);
    });
  });

  group('cpu', () {
    test('reaction delay and block chance follow the spec formulas', () {
      expect(CpuBrain.reactionDelay(4, 0.0), 24);
      expect(CpuBrain.reactionDelay(10, 1.0), 6);
      expect(CpuBrain.blockChance(0.0), closeTo(0.15, 1e-9));
      expect(CpuBrain.blockChance(1.0), closeTo(0.75, 1e-9));
    });
  });
}
