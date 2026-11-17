// Arcade CPU (spec 4.4). Pure Dart, seeded, so a fight replays the same way from the same seed.
// Real: approach / retreat / poke / punish / block / anti-air / special at full meter, reaction delay
// max(6, 30 - wit*1.5 - d*12) frames, block chance 0.15 + 0.6*d, temperament tweaks.
// Not here: learning from the player across fights (later, if wanted).
import 'dart:math';

import 'fighter.dart';
import 'input.dart';
import 'match_engine.dart';
import 'moves.dart';
import 'specials.dart';

class CpuBrain {
  final FighterDef def;

  /// 0.0 (first ladder fight) .. 1.0 (boss).
  final double difficulty;
  final int seed;
  final Random _rng;

  late final int reactionFrames = reactionDelay(def.stats.wit, difficulty);
  late final double aggression;
  late final double guard;
  late final double jumpiness;

  int _nextDecision = 0;
  int _moveDir = 0; // -1 away/left, +1 right; resolved each tick
  bool _approach = false;
  bool _retreat = false;
  int _press = 0;
  int _blockUntil = -1;
  int _techAt = -1;
  int _oppAttackStart = -1000;
  bool _oppAttackJudged = false;
  bool _punishTried = false;
  int _lastPress = 0;

  CpuBrain({required this.def, required this.difficulty, required this.seed})
    : _rng = Random(seed) {
    final t = {...def.temperament, def.archetype};
    var ag = 0.40 + difficulty * 0.30;
    var gd = blockChance(difficulty);
    var jp = 0.04;
    if (t.any(_aggressive.contains)) ag += 0.15;
    if (t.any(_defensive.contains)) gd += 0.12;
    if (t.any(_jumpy.contains)) jp += 0.10;
    aggression = ag.clamp(0.0, 0.95).toDouble();
    guard = gd.clamp(0.0, 0.92).toDouble();
    jumpiness = jp;
  }

  static const _aggressive = {
    'bold',
    'relentless',
    'restless',
    'direct',
    'intense',
    'proud',
    'vanguard',
    'champion',
  };
  static const _defensive = {
    'patient',
    'guarded',
    'steady',
    'disciplined',
    'stubborn',
    'warden',
    'keeper',
  };
  static const _jumpy = {
    'trickster',
    'elusive',
    'curious',
    'fickle',
    'free',
    'witty',
  };

  /// Reaction delay in frames: max(6, 30 - wit*1.5 - d*12).
  static int reactionDelay(int wit, double d) {
    final v = (30 - wit * 1.5 - d * 12).round();
    return v < 6 ? 6 : v;
  }

  /// Chance to block an attack that starts within range: 0.15 + 0.6*d.
  static double blockChance(double d) => 0.15 + 0.6 * d;

  double _specialRange(String id) {
    switch (id) {
      case 'flare_rush':
        return 170;
      case 'quake_stomp':
        return 90;
      case 'gale_step':
        return 320;
      case 'undertow':
        return 420;
      default:
        return 120;
    }
  }

  FighterIntent decide(MatchSnapshot s, int side) {
    if (s.phase != MatchPhase.fight) {
      _lastPress = 0;
      _techAt = -1;
      return FighterIntent.none;
    }
    final me = s.fighter(side);
    final opp = s.opponentOf(side);
    final frame = s.frame;
    final dx = opp.x - me.x;
    final dist = dx.abs();
    final toward = dx >= 0 ? FighterIntent.right : FighterIntent.left;
    final away = dx >= 0 ? FighterIntent.left : FighterIntent.right;

    // Watch the opponent's attacks start.
    if (opp.isAttacking && opp.actionFrames == 0) {
      _oppAttackStart = frame;
      _oppAttackJudged = false;
      _punishTried = false;
    }
    // Watch the opponent's throws: schedule a tech press inside the 6-frame
    // window. Better CPUs tech more often; the press itself is just the throw
    // button, recorded by the engine whatever state the CPU is in.
    if (opp.action == FighterAction.throwing &&
        opp.actionFrames == 0 &&
        dist <= 70 &&
        _techAt < 0 &&
        _rng.nextDouble() < 0.15 + 0.5 * difficulty) {
      _techAt = frame + 2 + _rng.nextInt(3);
    }
    final seen = frame - _oppAttackStart >= reactionFrames;

    var bits = 0;

    // Block: once the attack is "seen", roll once per attack.
    if (opp.isAttacking &&
        seen &&
        !_oppAttackJudged &&
        dist <= 120 &&
        me.grounded) {
      _oppAttackJudged = true;
      if (_rng.nextDouble() < guard) _blockUntil = frame + 24;
    }
    if (frame <= _blockUntil &&
        (opp.isAttacking || frame <= _blockUntil - 12)) {
      bits |= FighterIntent.block;
      // Stance: a low incoming attack is blocked crouching (the high/low rule).
      // S1 reads the height plainly; Wit-governed misreads land with the S3 polish.
      if (opp.isAttacking &&
          (opp.action == FighterAction.lp || opp.action == FighterAction.lk)) {
        bits |= FighterIntent.crouch;
      }
    } else if (!opp.isAttacking) {
      _blockUntil = -1;
    }

    if (frame == _techAt) {
      bits |= FighterIntent.throwBtn;
      _techAt = -1;
    }

    var press = 0;
    if (bits == 0) {
      // String follow-through (S3): mid-string, keep the string going — the
      // engine cancels LP/HP recovery into the next button, so a press now
      // continues the combo. After two connected LPs the finisher choice
      // follows the ruled Wit chance; at combo 3+ with a full meter, the
      // special cancel is the Elemental Finish.
      if ((me.action == FighterAction.lp || me.action == FighterAction.hp) &&
          me.combo > 0) {
        final m = me.action == FighterAction.lp ? Moves.lp : Moves.hp;
        if (m.isRecoveryAt(me.actionFrames)) {
          if (me.comboLpTail >= 2) {
            final p = 0.1 + def.stats.wit * 0.05 + difficulty * 0.3;
            if (_rng.nextDouble() < p.clamp(0.0, 0.95)) {
              press = _rng.nextBool() ? FighterIntent.hk : FighterIntent.hp;
            }
          } else if (me.action == FighterAction.lp &&
              _rng.nextDouble() <
                  0.3 + def.stats.wit * 0.05 + difficulty * 0.2) {
            press = FighterIntent.lp;
          }
        }
      }
      if (press == 0 &&
          me.combo >= 3 &&
          me.meter >= Moves.meterMax &&
          me.isAttacking &&
          me.action != FighterAction.special &&
          _rng.nextDouble() < 0.5) {
        press = FighterIntent.special;
      }
      // Punish a whiffed HK or special in its recovery.
      final whiffed =
          (opp.action == FighterAction.hk ||
              opp.action == FighterAction.special) &&
          opp.moveHits == 0 &&
          opp.actionFrames >
              (opp.action == FighterAction.hk
                  ? Moves.hk.startup + Moves.hk.active
                  : Moves.specialStartup + Moves.specialActive);
      if (whiffed && seen && !_punishTried && dist <= Moves.hk.range) {
        _punishTried = true;
        if (_rng.nextDouble() < 0.45 + 0.45 * difficulty) {
          press = FighterIntent.hk;
      }
      }
      // Anti-air: opponent jumping in.
      if (press == 0 && !opp.grounded && dist < 110 && opp.vy < 2) {
        if (_rng.nextDouble() < 0.02 + 0.10 * difficulty) {
          press = FighterIntent.hk;
      }
      }
      // Special at full meter when in its range.
      if (press == 0 && me.meter >= Moves.meterMax) {
        final id = def.isBoss
            ? Specials.all[me.specialCursor % Specials.all.length].id
            : def.specialId;
        if (dist <= _specialRange(id) &&
            _rng.nextDouble() < 0.04 + 0.10 * difficulty) {
          press = FighterIntent.special;
      }
      }
      // A fresh plan every reaction window.
      if (frame >= _nextDecision) {
        _nextDecision = frame + reactionFrames + _rng.nextInt(5);
        _plan(dist, me, opp);
      }
      if (press == 0 && _press != 0) {
        press = _press;
        _press = 0;
      }
      if (_approach) bits |= toward;
      if (_retreat) bits |= away;
      if (_moveDir != 0) {
        bits |= (_moveDir > 0 ? FighterIntent.right : FighterIntent.left);
    }
    }

    // Buttons must be released for a tick between presses (the engine reads rising edges).
    if (press != 0 && press == _lastPress) press = 0;
    _lastPress = press;
    return FighterIntent(bits | press);
  }

  void _plan(double dist, FighterState me, FighterState opp) {
    _approach = false;
    _retreat = false;
    _moveDir = 0;
    final r = _rng.nextDouble();
    final low = me.hpFraction < 0.3;
    if (dist > 90) {
      if (r < aggression) {
        _approach = true;
        if (_rng.nextDouble() < jumpiness) _press = FighterIntent.up;
      } else if (r < aggression + 0.1 && !low) {
        _press = FighterIntent.up;
        _approach = true;
      } else if (low && r > 0.8) {
        _retreat = true;
      }
      return;
    }
    // In range. A blocking opponent within grab range gets thrown (the
    // turtle tax); otherwise LP is the main poke (it chains), LK the low
    // mix-up, HK the commit.
    if (opp.blocking &&
        dist <= Moves.throwMove.range + 2 &&
        r < 0.30 + 0.30 * difficulty) {
      _press = FighterIntent.throwBtn;
    } else if (r < aggression * 0.40) {
      _press = FighterIntent.lp;
    } else if (r < aggression * 0.55) {
      _press = FighterIntent.lk;
    } else if (r < aggression * 0.55 + 0.18) {
      _press = FighterIntent.hk;
    } else if (r < aggression * 0.55 + 0.18 + jumpiness) {
      _press = FighterIntent.up;
      _retreat = _rng.nextBool();
    } else if (r < 0.85 || low) {
      _retreat = true;
    }
  }
}
