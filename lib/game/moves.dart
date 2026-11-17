// Move frame data (spec 4.3), 60 Hz frames. Pure Dart.
// Real: the exact numbers the MatchEngine uses. Specials' per-element behaviour is in specials.dart.
//
// Control-scheme slice S1 (Nov 16, 2026): light/heavy retired for the four-attack set
// HP / LP / HK / LK (Kiro's split). Every move carries a hit height: lows must be blocked low
// (block while crouching), overheads standing, mids either way.

/// Where a move hits, for the high/low block rule.
enum HitHeight { low, mid, overhead }

class MoveData {
  final String id;
  final int startup;
  final int active;
  final int recovery;

  /// Base damage before the attacker's power multiplier.
  final int damage;

  /// Horizontal reach from the attacker's centre, px.
  final double range;

  /// Pushback on hit, px.
  final double knockback;

  /// Highest target height (px above ground) a grounded version of this move reaches.
  final double reachUp;

  /// How many times one use can hit (1 for everything but Flare Rush).
  final int maxHits;

  /// Hit height for the block rule (specials default to mid until S4 gives them heights).
  final HitHeight height;

  /// How many times this move can chain into itself from its own recovery (LP 3, HP 2, kicks 0).
  final int chainMax;

  const MoveData({
    required this.id,
    required this.startup,
    required this.active,
    required this.recovery,
    required this.damage,
    required this.range,
    this.knockback = 0,
    this.reachUp = 40,
    this.maxHits = 1,
    this.height = HitHeight.mid,
    this.chainMax = 0,
  });

  int get total => startup + active + recovery;

  /// Hitstun a hit from this move causes: active + 6 frames.
  int get hitstun => active + 6;

  bool isActiveAt(int frame) => frame >= startup && frame < startup + active;
  bool isRecoveryAt(int frame) => frame >= startup + active;
}

class Moves {
  Moves._();

  /// HP (high punch): 4/3/8, 6 dmg, 70 px. The old light, promoted; chains up to 2. A mid.
  static const hp = MoveData(
    id: 'hp',
    startup: 4,
    active: 3,
    recovery: 8,
    damage: 6,
    range: 70,
    knockback: 4,
    reachUp: 40,
    chainMax: 2,
  );

  /// LP (low punch): 3/2/8, 4 dmg, 55 px. Fastest move in the game; chains up to 3
  /// (the old light-chain lives here). A low: blocked only by a low block.
  static const lp = MoveData(
    id: 'lp',
    startup: 3,
    active: 2,
    recovery: 8,
    damage: 4,
    range: 55,
    knockback: 2,
    reachUp: 30,
    height: HitHeight.low,
    chainMax: 3,
  );

  /// HK (high kick): 10/4/16, 13 dmg, 85 px, knockback 20 px. The old heavy; reaches
  /// higher, so it works as an anti-air. A mid.
  static const hk = MoveData(
    id: 'hk',
    startup: 10,
    active: 4,
    recovery: 16,
    damage: 13,
    range: 85,
    knockback: 20,
    reachUp: 70,
  );

  /// LK (low kick): 7/3/12, 8 dmg, 75 px, knockback 10 px. The low poke.
  /// A low: blocked only by a low block.
  static const lk = MoveData(
    id: 'lk',
    startup: 7,
    active: 3,
    recovery: 12,
    damage: 8,
    range: 75,
    knockback: 10,
    reachUp: 30,
    height: HitHeight.low,
  );

  /// One-Two (S3): the HP that finishes an LP-LP string — base damage 6 -> 9.
  /// Selected by the engine while the attacker's finisher mark is 'one_two'.
  static const hpOneTwo = MoveData(
    id: 'hp_one_two',
    startup: 4,
    active: 3,
    recovery: 8,
    damage: 9,
    range: 70,
    knockback: 4,
    reachUp: 40,
  );

  /// Plaza Finisher (S3): the HK that finishes an LP-LP string — startup
  /// 10 -> 6, damage 13 -> 17, knockback 20 -> 26. The marquee string.
  static const hkPlaza = MoveData(
    id: 'hk_plaza',
    startup: 6,
    active: 4,
    recovery: 16,
    damage: 17,
    range: 85,
    knockback: 26,
    reachUp: 70,
  );

  /// Combo score bonus banked when a combo ends, per hit past the first (S3).
  static const comboBonusPerHit = 50;

  /// Block: 2 frames to raise, held, then [FighterStats.blockRecovery] (6 at resolve 6) to drop.
  static const blockStartup = 2;

  /// Blocked hits deal 20% chip damage.
  static const chipFraction = 0.2;

  /// 3 blocked hits within 60 frames break the guard for 40 frames.
  static const guardBreakHits = 3;
  static const guardBreakWindow = 60;
  static const guardBreakStun = 40;

  /// Jump: 3 frames of startup on the ground, 4 frames of landing lag.
  static const jumpStartup = 3;
  static const jumpLanding = 4;

  /// Special: 14/6/24, 22 dmg base; range and behaviour per element (specials.dart).
  static const specialStartup = 14;
  static const specialActive = 6;
  static const specialRecovery = 24;
  static const specialDamage = 22;

  /// Throw (S2): 5/2/16, 10 dmg, 50 px — you must be *on* them — knockback 24.
  /// Unblockable; resolved specially by the engine (see MatchEngine._resolveThrows),
  /// never through the strike path, so it cannot be combo'd into.
  static const throwMove = MoveData(
    id: 'throw',
    startup: 5,
    active: 2,
    recovery: 16,
    damage: 10,
    range: 50,
    knockback: 24,
    reachUp: 30,
  );

  /// Stun a landed throw causes: a long, knockdown-style 26 frames.
  static const throwStun = 26;

  /// A defender pressing throw within this many frames of the grab connecting techs it.
  static const throwTechWindow = 6;

  /// Pushback each fighter takes on a throw-tech, px.
  static const throwTechPushback = 8;

  /// Full meter, what a special costs.
  static const meterMax = 100;
  static const meterOnHit = 8;
  static const meterOnBlock = 4;
}
