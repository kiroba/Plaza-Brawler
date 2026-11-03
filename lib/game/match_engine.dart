// Plaza Brawler match engine (spec 4.3). Pure Dart, fixed 60 Hz tick, no Flutter imports.
// Real: movement, jump, light/heavy/block/special frame data, chip damage, guard break, meter, the four
// element specials (incl. the Undertow projectile), best-of-3 rounds with a 60 s timer, match summary
// events and a deterministic stateBytes()/stateHash() for lockstep later.
// Started from Gemini's match_engine.dart; numbers and hit logic were brought in line with the spec.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'fighter.dart';
import 'input.dart';
import 'moves.dart';
import 'specials.dart';

enum MatchPhase { intro, fight, roundOver, matchOver }

/// An Undertow projectile in flight.
class Projectile {
  final int owner;
  double x;
  final double y;
  final int dir;
  int life;
  Projectile({
    required this.owner,
    required this.x,
    required this.y,
    required this.dir,
    required this.life,
  });
}

/// How one round ended.
class RoundResult {
  final int round;

  /// 0 = P1, 1 = P2, null = draw.
  final int? winner;
  final bool ko;
  final int winnerHp;
  final int winnerMaxHp;
  final int framesLeft;

  const RoundResult({
    required this.round,
    required this.winner,
    required this.ko,
    required this.winnerHp,
    required this.winnerMaxHp,
    required this.framesLeft,
  });

  bool get timeout => !ko;
  bool get perfect => winner != null && winnerHp == winnerMaxHp;
  int get secondsLeft => framesLeft ~/ 60;

  Map<String, dynamic> toJson() => {
    'round': round,
    'winner': winner == null ? 'draw' : (winner == 0 ? 'p1' : 'p2'),
    'ko': ko,
    'winner_hp': winnerHp,
    'seconds_left': secondsLeft,
    'perfect': perfect,
  };
}

/// A signed-event-worthy moment: FIGHTER_MATCH_START, FIGHTER_ROUND_END, FIGHTER_MATCH_END.
/// (No per-hit events: hit counts live in the match summary.)
class MatchEvent {
  final String type;
  final Map<String, dynamic> payload;
  const MatchEvent(this.type, this.payload);
}

/// One visual cue for the art layer (hit flash, shake). Not part of the game state or its hash.
class HitFx {
  final int defender;
  final bool blocked;
  final bool heavy;
  final bool special;
  final bool guardBreak;
  final bool ko;
  const HitFx({
    required this.defender,
    required this.blocked,
    required this.heavy,
    required this.special,
    this.guardBreak = false,
    this.ko = false,
  });
}

/// Read-only view of the match handed to InputSources and the UI each tick.
class MatchSnapshot {
  final MatchEngine _e;
  MatchSnapshot(this._e);

  int get frame => _e.frame;
  MatchPhase get phase => _e.phase;
  int get round => _e.round;
  int get roundFramesLeft => _e.roundFramesLeft;
  int get secondsLeft => (_e.roundFramesLeft + 59) ~/ 60;
  FighterState fighter(int side) => side == 0 ? _e.p1 : _e.p2;
  FighterState opponentOf(int side) => side == 0 ? _e.p2 : _e.p1;
  List<Projectile> get projectiles => List.unmodifiable(_e.projectiles);
  int wins(int side) => _e.wins[side];
  double distance() => (_e.p1.x - _e.p2.x).abs();
}

class _Hit {
  final int attacker;
  final FighterState a;
  final FighterState d;
  final MoveData move;
  final bool unblockable;
  final bool special;
  final bool heavy;

  /// Direction the hit pushes the defender (+1 right, -1 left).
  final int dir;
  final double pull;
  final double originX;
  final bool melee;
  const _Hit({
    required this.attacker,
    required this.a,
    required this.d,
    required this.move,
    required this.dir,
    required this.originX,
    this.unblockable = false,
    this.special = false,
    this.heavy = false,
    this.pull = 0,
    this.melee = true,
  });
}

class MatchEngine {
  static const double arenaWidth = 640;
  static const double arenaHeight = 360;
  static const double minX = 30;
  static const double maxX = arenaWidth - 30;
  static const double gravity = 0.6;
  static const double minSpacing = 40;
  static const double startX1 = 200;
  static const double startX2 = 440;
  static const int ticksPerSecond = 60;
  static const int roundFrames = 60 * ticksPerSecond;
  static const int introFrames = 60;
  static const int roundOverFrames = 120;
  static const int winsNeeded = 2;
  static const int maxRounds = 5;
  static const int bufferWindow = 6;

  final FighterState p1;
  final FighterState p2;
  InputSource? input1;
  // PvP hook: in the multiplayer PR, input2 becomes a RemoteInput fed by the lockstep buffer.
  InputSource? input2;
  final int seed;
  final String mode;

  int frame = 0;
  MatchPhase phase = MatchPhase.intro;
  int phaseFrames = 0;
  int round = 1;
  int roundFramesLeft = roundFrames;
  final List<int> wins = [0, 0];
  final List<RoundResult> results = [];
  final List<Projectile> projectiles = [];

  final List<MatchEvent> _events = [];
  final List<HitFx> fx = [];

  /// 0, 1, or null for a draw. Set when [phase] is matchOver.
  int? matchWinner;

  late final MatchSnapshot snapshot = MatchSnapshot(this);

  MatchEngine({
    required FighterDef p1,
    required FighterDef p2,
    this.input1,
    this.input2,
    this.seed = 0,
    this.mode = 'quick',
  }) : p1 = FighterState(p1, x: startX1, facingRight: true),
       p2 = FighterState(p2, x: startX2, facingRight: false) {
    _events.add(
      MatchEvent('FIGHTER_MATCH_START', {
        'mode': mode,
        'p1_sign': p1.sign,
        'p1_source': p1.source,
        'p2_sign': p2.sign,
        'p2_source': p2.source,
        'seed': seed,
      }),
    );
  }

  bool get isOver => phase == MatchPhase.matchOver;
  FighterState fighter(int side) => side == 0 ? p1 : p2;

  /// Events since the last call (the UI signs them with omniNode.dispatchEvent).
  List<MatchEvent> drainEvents() {
    final out = List<MatchEvent>.from(_events);
    _events.clear();
    return out;
  }

  /// One 60 Hz step, polling both input sources.
  void tick() {
    final a = input1?.poll(snapshot) ?? FighterIntent.none;
    final b = input2?.poll(snapshot) ?? FighterIntent.none;
    tickWith(a, b);
  }

  /// One 60 Hz step with explicit intents (tests, replays, lockstep).
  void tickWith(FighterIntent a, FighterIntent b) {
    fx.clear();
    if (phase == MatchPhase.matchOver) return;
    frame++;
    switch (phase) {
      case MatchPhase.intro:
        phaseFrames++;
        p1.prevBits = a.bits;
        p2.prevBits = b.bits;
        if (phaseFrames >= introFrames) {
          phase = MatchPhase.fight;
          phaseFrames = 0;
        }
        return;
      case MatchPhase.roundOver:
        phaseFrames++;
        _physics(p1);
        _physics(p2);
        if (phaseFrames >= roundOverFrames) _afterRound();
        return;
      case MatchPhase.matchOver:
        return;
      case MatchPhase.fight:
        break;
    }

    roundFramesLeft--;
    _face(p1, p2);
    _face(p2, p1);
    _act(p1, a, p2);
    _act(p2, b, p1);
    _physics(p1);
    _physics(p2);
    _separate();
    _moveProjectiles();

    // Collect both sides' hits against the same positions, then apply (so hits can trade).
    final hits = <_Hit>[
      ..._meleeHits(0),
      ..._meleeHits(1),
      ..._projectileHits(),
    ];
    for (final h in hits) {
      _apply(h);
    }
    _checkRoundEnd();
  }

  // ---------------------------------------------------------------- per-fighter logic

  void _face(FighterState f, FighterState o) {
    if (f.isAttacking ||
        f.action == FighterAction.hitstun ||
        f.isKo ||
        !f.grounded)
      return;
    if (f.x != o.x) f.facingRight = o.x > f.x;
  }

  MoveData _moveOf(FighterState f) {
    switch (f.action) {
      case FighterAction.light:
        return Moves.light;
      case FighterAction.heavy:
        return Moves.heavy;
      case FighterAction.special:
        return Specials.byId(f.activeSpecial).move;
      default:
        return Moves.light;
    }
  }

  void _start(FighterState f, FighterAction a) {
    f.action = a;
    f.actionFrames = 0;
    f.moveHits = 0;
    f.lastHitFrame = -100;
    f.bufBits = 0;
    f.bufFrames = 0;
  }

  void _act(FighterState f, FighterIntent intent, FighterState o) {
    final bits = intent.bits;
    final pressed = bits & ~f.prevBits;
    f.prevBits = bits;
    const bufferable =
        FighterIntent.light |
        FighterIntent.heavy |
        FighterIntent.special |
        FighterIntent.up;
    if (pressed & bufferable != 0) {
      f.bufBits = pressed & bufferable;
      f.bufFrames = bufferWindow;
    } else if (f.bufFrames > 0) {
      f.bufFrames--;
      if (f.bufFrames == 0) f.bufBits = 0;
    }
    final want = pressed | f.bufBits;
    bool wants(int flag) => want & flag != 0;
    final holdBlock = intent.has(FighterIntent.block);

    switch (f.action) {
      case FighterAction.ko:
        return;
      case FighterAction.hitstun:
        if (f.stunFrames > 0) f.stunFrames--;
        if (f.stunFrames <= 0) {
          f.action = f.grounded ? FighterAction.idle : FighterAction.jump;
          f.actionFrames = f.grounded ? 0 : Moves.jumpStartup;
        }
        return;
      case FighterAction.light:
      case FighterAction.heavy:
      case FighterAction.special:
        f.actionFrames++;
        final m = _moveOf(f);
        if (f.action == FighterAction.special) _specialStep(f, o);
        // Light chain: another light during recovery restarts it, up to 3 in a row (ground only).
        if (f.action == FighterAction.light &&
            !f.airAttack &&
            m.isRecoveryAt(f.actionFrames) &&
            wants(FighterIntent.light) &&
            f.chain < Moves.lightChain) {
          f.chain++;
          _start(f, FighterAction.light);
          return;
        }
        if (f.actionFrames >= m.total) {
          f.chain = 0;
          f.activeSpecial = '';
          if (f.airAttack && !f.grounded) {
            f.airAttack = false;
            f.action = FighterAction.jump;
            f.actionFrames = Moves.jumpStartup;
          } else {
            f.airAttack = false;
            f.action = FighterAction.idle;
            f.actionFrames = 0;
          }
        }
        return;
      case FighterAction.block:
        f.actionFrames++;
        if (f.lag > 0) {
          // Dropping the block: recovery frames before anything else.
          f.lag--;
          if (f.lag == 0) {
            f.action = FighterAction.idle;
            f.actionFrames = 0;
          }
          return;
        }
        if (holdBlock) {
          if (f.actionFrames >= Moves.blockStartup) f.blocking = true;
          return;
        }
        if (f.blocking) {
          f.blocking = false;
          f.lag = f.def.stats.blockRecovery;
          return;
        }
        f.action = FighterAction.idle;
        f.actionFrames = 0;
        return;
      case FighterAction.jump:
        f.actionFrames++;
        if (f.grounded && f.vy == 0 && f.actionFrames == Moves.jumpStartup) {
          f.vy = f.def.stats.jumpVelocity;
          f.vx = intent.dir * f.def.stats.walkSpeed;
          f.y = 0.01;
          return;
        }
        if (!f.grounded && wants(FighterIntent.light)) {
          f.airAttack = true;
          f.chain = 1;
          _start(f, FighterAction.light);
        }
        return;
      case FighterAction.idle:
      case FighterAction.walk:
        if (f.lag > 0) {
          f.lag--;
          f.action = FighterAction.idle;
          return;
        }
        if (wants(FighterIntent.special) &&
            f.meter >= Moves.meterMax &&
            f.grounded) {
          _startSpecial(f);
          return;
        }
        if (wants(FighterIntent.heavy) && f.grounded) {
          f.chain = 0;
          _start(f, FighterAction.heavy);
          return;
        }
        if (wants(FighterIntent.light)) {
          f.chain = 1;
          f.airAttack = !f.grounded;
          _start(f, FighterAction.light);
          return;
        }
        if (holdBlock && f.grounded) {
          _start(f, FighterAction.block);
          return;
        }
        if (wants(FighterIntent.up) && f.grounded) {
          _start(f, FighterAction.jump);
          return;
        }
        final d = intent.dir;
        if (d != 0 && f.grounded) {
          f.x = _clampX(f.x + d * f.def.stats.walkSpeed);
          f.action = FighterAction.walk;
          f.actionFrames++;
        } else {
          f.action = FighterAction.idle;
          f.actionFrames = 0;
        }
        return;
    }
  }

  void _startSpecial(FighterState f) {
    f.meter -= Moves.meterMax;
    f.specialsUsed++;
    final SpecialDef s;
    if (f.def.isBoss) {
      s = Specials.all[f.specialCursor % Specials.all.length];
      f.specialCursor++;
    } else {
      s = Specials.byId(f.def.specialId);
    }
    f.activeSpecial = s.id;
    f.chain = 0;
    _start(f, FighterAction.special);
  }

  void _specialStep(FighterState f, FighterState o) {
    final s = Specials.byId(f.activeSpecial);
    final m = s.move;
    switch (s.kind) {
      case SpecialKind.teleportHeavy:
        if (f.actionFrames == m.startup) {
          final side = f.x <= o.x
              ? 1
              : -1; // attacker is left of the opponent -> land on its right
          var nx = o.x + side * 50;
          if (nx < minX || nx > maxX) nx = o.x - side * 50;
          f.x = _clampX(nx);
          f.facingRight = o.x > f.x;
        }
        break;
      case SpecialKind.dashMultiHit:
        if (m.isActiveAt(f.actionFrames)) {
          final step = s.dashDistance / m.active;
          final dir = f.facingRight ? 1 : -1;
          var nx = f.x + dir * step;
          final stop = o.x - dir * minSpacing;
          if (dir > 0 && f.x <= stop && nx > stop) nx = stop;
          if (dir < 0 && f.x >= stop && nx < stop) nx = stop;
          f.x = _clampX(nx);
        }
        break;
      case SpecialKind.projectilePull:
        if (f.actionFrames == m.startup) {
          final dir = f.facingRight ? 1 : -1;
          projectiles.add(
            Projectile(
              owner: f == p1 ? 0 : 1,
              x: f.x + dir * 30,
              y: 30,
              dir: dir,
              life: s.projectileLife,
            ),
          );
        }
        break;
      case SpecialKind.shockwave:
        break;
    }
  }

  void _physics(FighterState f) {
    if (f.y > 0 || f.vy > 0) {
      f.y += f.vy;
      f.vy -= gravity;
      f.x = _clampX(f.x + f.vx);
      if (f.y <= 0) {
        f.y = 0;
        f.vy = 0;
        f.vx = 0;
        if (f.action == FighterAction.jump) {
          f.action = FighterAction.idle;
          f.actionFrames = 0;
          f.lag = Moves.jumpLanding;
        } else if (f.action == FighterAction.light && f.airAttack) {
          f.action = FighterAction.idle;
          f.actionFrames = 0;
          f.airAttack = false;
          f.chain = 0;
          f.lag = Moves.jumpLanding;
        }
      }
    }
  }

  void _separate() {
    final dx = p2.x - p1.x;
    if (dx.abs() >= minSpacing || (p1.y - p2.y).abs() > 60) return;
    final p1Left = dx > 0 || (dx == 0 && p1.facingRight);
    final overlap = (minSpacing - dx.abs()) / 2;
    final l = p1Left ? p1 : p2;
    final r = p1Left ? p2 : p1;
    l.x -= overlap;
    r.x += overlap;
    if (l.x < minX) {
      r.x += minX - l.x;
      l.x = minX;
    }
    if (r.x > maxX) {
      l.x -= r.x - maxX;
      r.x = maxX;
    }
  }

  void _moveProjectiles() {
    for (final p in projectiles) {
      p.x += p.dir * Specials.undertow.projectileSpeed;
      p.life--;
    }
    projectiles.removeWhere((p) => p.life <= 0 || p.x < 0 || p.x > arenaWidth);
  }

  static int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  double _clampX(double x) => x < minX ? minX : (x > maxX ? maxX : x);

  // ---------------------------------------------------------------- hits

  List<_Hit> _meleeHits(int side) {
    final a = fighter(side);
    final d = fighter(1 - side);
    if (!a.isAttacking || d.isKo) return const [];
    final m = _moveOf(a);
    if (a.action == FighterAction.special &&
        Specials.byId(a.activeSpecial).kind == SpecialKind.projectilePull) {
      return const []; // Undertow hits through its projectile only.
    }
    // The multi-hit fix: one hit per move use, except Flare Rush (3 hits, hitSpacing frames apart).
    if (a.moveHits >= m.maxHits) return const [];
    const spacing = Specials.flareRushHitSpacing;
    if (m.maxHits > 1 && a.actionFrames - a.lastHitFrame < spacing)
      return const [];
    // Once a multi-hit move connects, its follow-ups keep their cadence even past the active frames, so a
    // Flare Rush that makes contact late in its dash still lands all 3 hits.
    final followUp =
        m.maxHits > 1 &&
        a.moveHits > 0 &&
        a.actionFrames - a.lastHitFrame <= 2 * spacing;
    if (!m.isActiveAt(a.actionFrames) && !followUp) return const [];
    final dx = d.x - a.x;
    final inFront = a.facingRight ? dx >= -10 : dx <= 10;
    // Follow-ups reach as far as the earlier hits pushed the defender.
    final reach = m.range + (followUp ? m.knockback * a.moveHits : 0);
    if (!inFront || dx.abs() > reach) return const [];
    if (a.airAttack) {
      if ((d.y - a.y).abs() > 80 || d.y > a.y + 40) return const [];
    } else if (d.y > m.reachUp) {
      return const [];
    }
    return [
      _Hit(
        attacker: side,
        a: a,
        d: d,
        move: m,
        dir: a.facingRight ? 1 : -1,
        originX: a.x,
        unblockable: a.airAttack, // an air light hits a blocking opponent
        special: a.action == FighterAction.special,
        heavy: a.action == FighterAction.heavy,
      ),
    ];
  }

  List<_Hit> _projectileHits() {
    final out = <_Hit>[];
    for (final p in projectiles) {
      if (p.life <= 0) continue;
      final a = fighter(p.owner);
      final d = fighter(1 - p.owner);
      if (d.isKo) continue;
      if ((p.x - d.x).abs() <= Specials.undertow.move.range &&
          d.y <= Specials.undertow.move.reachUp) {
        out.add(
          _Hit(
            attacker: p.owner,
            a: a,
            d: d,
            move: Specials.undertow.move,
            dir: p.dir,
            originX: p.x - p.dir * 10,
            special: true,
            pull: Specials.undertow.pull,
            melee: false,
          ),
        );
        p.life = 0;
      }
    }
    projectiles.removeWhere((p) => p.life <= 0);
    return out;
  }

  int _damage(FighterState a, MoveData m) =>
      (m.damage * a.def.stats.damageMultiplier).round();

  void _apply(_Hit h) {
    final a = h.a, d = h.d;
    if (d.isKo && d.hp <= 0) return;
    if (h.melee) {
      a.moveHits++;
      a.lastHitFrame = a.actionFrames;
    }
    final dmg = _damage(a, h.move);
    final facesAttacker = d.facingRight == (h.originX > d.x);
    final blocked =
        !h.unblockable &&
        d.blocking &&
        d.grounded &&
        d.action == FighterAction.block &&
        facesAttacker;
    if (blocked) {
      final chip = _ci((dmg * Moves.chipFraction).round(), 1, dmg);
      d.hp = _ci(d.hp - chip, 0, d.maxHp);
      a.meter = _ci(a.meter + Moves.meterOnBlock, 0, Moves.meterMax);
      a.hitsBlocked++;
      a.damageDealt += chip;
      d.x = _clampX(d.x + h.dir * h.move.knockback / 2);
      d.blockedAt.add(frame);
      d.blockedAt.removeWhere((t) => frame - t >= Moves.guardBreakWindow);
      var broke = false;
      if (d.blockedAt.length >= Moves.guardBreakHits) {
        d.blockedAt.clear();
        d.blocking = false;
        d.lag = 0;
        d.action = FighterAction.hitstun;
        d.stunFrames = Moves.guardBreakStun;
        a.guardBreaks++;
        broke = true;
      }
      if (d.hp <= 0) _ko(d);
      fx.add(
        HitFx(
          defender: d == p1 ? 0 : 1,
          blocked: true,
          heavy: h.heavy,
          special: h.special,
          guardBreak: broke,
          ko: d.isKo,
        ),
      );
      return;
    }
    d.hp = _ci(d.hp - dmg, 0, d.maxHp);
    a.meter = _ci(a.meter + Moves.meterOnHit, 0, Moves.meterMax);
    a.hitsLanded++;
    a.damageDealt += dmg;
    // The hit cancels whatever the defender was doing.
    d.blocking = false;
    d.lag = 0;
    d.chain = 0;
    d.airAttack = false;
    d.activeSpecial = '';
    d.bufBits = 0;
    d.bufFrames = 0;
    d.action = FighterAction.hitstun;
    d.actionFrames = 0;
    d.stunFrames = h.move.hitstun;
    if (h.pull > 0) {
      // Undertow pulls toward the caster, never past it.
      final toward = a.x > d.x ? 1 : -1;
      var nx = d.x + toward * h.pull;
      final limit = a.x - toward * minSpacing;
      if (toward > 0 && nx > limit) nx = limit;
      if (toward < 0 && nx < limit) nx = limit;
      d.x = _clampX(nx);
    } else {
      d.x = _clampX(d.x + h.dir * h.move.knockback);
    }
    if (d.hp <= 0) _ko(d);
    fx.add(
      HitFx(
        defender: d == p1 ? 0 : 1,
        blocked: false,
        heavy: h.heavy,
        special: h.special,
        ko: d.isKo,
      ),
    );
  }

  void _ko(FighterState f) {
    f.hp = 0;
    f.action = FighterAction.ko;
    f.blocking = false;
    f.activeSpecial = '';
  }

  // ---------------------------------------------------------------- rounds

  void _checkRoundEnd() {
    final ko1 = p1.hp <= 0, ko2 = p2.hp <= 0;
    int? winner;
    bool ko;
    if (ko1 || ko2) {
      ko = true;
      winner = (ko1 && ko2) ? null : (ko1 ? 1 : 0);
    } else if (roundFramesLeft <= 0) {
      ko = false;
      final f1 = p1.hpFraction, f2 = p2.hpFraction;
      winner = f1 == f2 ? null : (f1 > f2 ? 0 : 1);
    } else {
      return;
    }
    final w = winner == null ? null : fighter(winner);
    final r = RoundResult(
      round: round,
      winner: winner,
      ko: ko,
      winnerHp: w?.hp ?? 0,
      winnerMaxHp: w?.maxHp ?? 0,
      framesLeft: roundFramesLeft < 0 ? 0 : roundFramesLeft,
    );
    results.add(r);
    if (winner != null) wins[winner]++;
    projectiles.clear();
    _events.add(
      MatchEvent('FIGHTER_ROUND_END', {
        'mode': mode,
        ...r.toJson(),
        'p1_hp': p1.hp,
        'p2_hp': p2.hp,
        'wins': [wins[0], wins[1]],
      }),
    );
    phase = MatchPhase.roundOver;
    phaseFrames = 0;
  }

  bool get _decided =>
      wins[0] >= winsNeeded ||
      wins[1] >= winsNeeded ||
      results.length >= maxRounds;

  void _afterRound() {
    if (_decided) {
      phase = MatchPhase.matchOver;
      matchWinner = wins[0] == wins[1] ? null : (wins[0] > wins[1] ? 0 : 1);
      _events.add(MatchEvent('FIGHTER_MATCH_END', summary()));
      return;
    }
    round++;
    roundFramesLeft = roundFrames;
    p1.resetForRound(x: startX1, facingRight: true);
    p2.resetForRound(x: startX2, facingRight: false);
    phase = MatchPhase.intro;
    phaseFrames = 0;
  }

  /// The match summary (the FIGHTER_MATCH_END payload). Hit counts replace per-hit events.
  Map<String, dynamic> summary() {
    Map<String, dynamic> side(FighterState f) => {
      'sign': f.def.sign,
      'source': f.def.source,
      'hits_landed': f.hitsLanded,
      'hits_blocked': f.hitsBlocked,
      'specials': f.specialsUsed,
      'guard_breaks': f.guardBreaks,
      'damage': f.damageDealt,
    };
    return {
      'mode': mode,
      'winner': matchWinner == null ? 'draw' : (matchWinner == 0 ? 'p1' : 'p2'),
      'wins': [wins[0], wins[1]],
      'rounds': [for (final r in results) r.toJson()],
      'frames': frame,
      'duration_ms': frame * 1000 ~/ ticksPerSecond,
      'seed': seed,
      'p1': side(p1),
      'p2': side(p2),
      'final_state_hash': stateHash(),
    };
  }

  // ---------------------------------------------------------------- determinism

  /// Every value that affects future ticks, in a fixed order. Same seed + same inputs -> same bytes.
  Uint8List stateBytes() {
    final b = BytesBuilder(copy: false);
    final bd = ByteData(8);
    void i32(int v) {
      bd.setInt32(0, v, Endian.little);
      b.add(bd.buffer.asUint8List(0, 4).toList());
    }

    void f64(double v) {
      bd.setFloat64(0, v, Endian.little);
      b.add(bd.buffer.asUint8List(0, 8).toList());
    }

    void str(String s) {
      i32(s.length);
      for (final c in s.codeUnits) {
        i32(c);
      }
    }

    i32(frame);
    i32(phase.index);
    i32(phaseFrames);
    i32(round);
    i32(roundFramesLeft);
    i32(wins[0]);
    i32(wins[1]);
    i32(results.length);
    for (final f in [p1, p2]) {
      f64(f.x);
      f64(f.y);
      f64(f.vy);
      f64(f.vx);
      i32(f.hp);
      i32(f.meter);
      i32(f.action.index);
      i32(f.actionFrames);
      i32(f.facingRight ? 1 : 0);
      i32(f.blocking ? 1 : 0);
      i32(f.stunFrames);
      i32(f.chain);
      i32(f.moveHits);
      i32(f.lastHitFrame);
      i32(f.lag);
      i32(f.blockedAt.length);
      for (final t in f.blockedAt) {
        i32(t);
      }
      i32(f.specialCursor);
      str(f.activeSpecial);
      i32(f.airAttack ? 1 : 0);
      i32(f.prevBits);
      i32(f.bufBits);
      i32(f.bufFrames);
      i32(f.hitsLanded);
      i32(f.hitsBlocked);
      i32(f.specialsUsed);
      i32(f.guardBreaks);
      i32(f.damageDealt);
    }
    i32(projectiles.length);
    for (final p in projectiles) {
      i32(p.owner);
      f64(p.x);
      f64(p.y);
      i32(p.dir);
      i32(p.life);
    }
    return b.toBytes();
  }

  /// sha256 of [stateBytes], hex. Used for the desync check in the multiplayer PR.
  String stateHash() => sha256.convert(stateBytes()).toString();
}
