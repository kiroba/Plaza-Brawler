// Move frame data (spec 4.3), 60 Hz frames. Pure Dart.
// Real: the exact numbers the MatchEngine uses. Specials' per-element behaviour is in specials.dart.

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
  });

  int get total => startup + active + recovery;

  /// Hitstun a hit from this move causes: active + 6 frames.
  int get hitstun => active + 6;

  bool isActiveAt(int frame) => frame >= startup && frame < startup + active;
  bool isRecoveryAt(int frame) => frame >= startup + active;
}

class Moves {
  Moves._();

  /// Light (punch): 4/3/8, 6 dmg, 70 px, chains up to 3.
  static const light = MoveData(
    id: 'light',
    startup: 4,
    active: 3,
    recovery: 8,
    damage: 6,
    range: 70,
    knockback: 4,
    reachUp: 40,
  );

  /// Heavy (kick): 10/4/16, 13 dmg, 85 px, knockback 20 px. Reaches higher, so it works as an anti-air.
  static const heavy = MoveData(
    id: 'heavy',
    startup: 10,
    active: 4,
    recovery: 16,
    damage: 13,
    range: 85,
    knockback: 20,
    reachUp: 70,
  );

  /// Max light attacks in one chain.
  static const lightChain = 3;

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

  /// Full meter, what a special costs.
  static const meterMax = 100;
  static const meterOnHit = 8;
  static const meterOnBlock = 4;
}
