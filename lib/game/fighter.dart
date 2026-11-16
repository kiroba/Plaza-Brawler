// Fighter model for Plaza Brawler (spec 4.1). Pure Dart, no Flutter imports.
// Real: stats -> fight numbers (damage multiplier, walk speed, jump, max HP, block recovery) and the
// mutable per-tick FighterState the MatchEngine drives. Colours are ARGB ints so this file stays
// testable without Flutter; the art layer turns them into Color.

/// The four zodiac stats, each 1..10 (same scale as the daemon's zodiac generator).
class FighterStats {
  final int power;
  final int agility;
  final int wit;
  final int resolve;

  const FighterStats({
    required this.power,
    required this.agility,
    required this.wit,
    required this.resolve,
  });

  static int _c(int v) => v < 1 ? 1 : (v > 10 ? 10 : v);

  /// Clamps every stat into 1..10.
  FighterStats clamped() => FighterStats(
    power: _c(power),
    agility: _c(agility),
    wit: _c(wit),
    resolve: _c(resolve),
  );

  /// Damage multiplier: 0.8 + power * 0.04.
  double get damageMultiplier => 0.8 + power * 0.04;

  /// Walk speed in px per tick: 2.5 + agility * 0.25.
  double get walkSpeed => 2.5 + agility * 0.25;

  /// Initial jump velocity (px per tick, upward). Agility adds height.
  double get jumpVelocity => 9.0 + agility * 0.3;

  /// Max HP: 90 + resolve * 2.
  int get maxHp => 90 + resolve * 2;

  /// Frames to drop a block. Higher resolve recovers faster (base 6 at resolve 6).
  int get blockRecovery {
    final v = 8 - resolve ~/ 3;
    return v < 3 ? 3 : v;
  }

  List<int> toList() => [power, agility, wit, resolve];

  Map<String, int> toJson() => {
    'power': power,
    'agility': agility,
    'wit': wit,
    'resolve': resolve,
  };

  @override
  bool operator ==(Object other) =>
      other is FighterStats &&
      other.power == power &&
      other.agility == agility &&
      other.wit == wit &&
      other.resolve == resolve;

  @override
  int get hashCode => Object.hash(power, agility, wit, resolve);

  @override
  String toString() => 'FighterStats($power, $agility, $wit, $resolve)';
}

/// One layer of the daemon's 5-layer manifest (body, palette, outfit, accessory, aura).
class FighterLayer {
  final String layer;
  final String assetId;
  final int z;

  /// ARGB colour (opaque) from the manifest's #rrggbb tint.
  final int tint;

  /// 0..100 percent.
  final int opacity;

  const FighterLayer({
    required this.layer,
    required this.assetId,
    required this.z,
    required this.tint,
    this.opacity = 100,
  });
}

/// Sprite binding from a figure pack (OmniStudio .omnimod): the bundled asset
/// paths the art layer draws instead of the painted fighter. Pure data (paths
/// only) so this file stays Flutter-free; the UI layer resolves and decodes.
/// Null on a FighterDef means "painted fighter", as every fighter was before
/// packs.
class FighterSpriteBinding {
  /// Asset path of the pack portrait (select screens, VS splash, game over).
  final String portraitAsset;

  /// Asset path of the three-quarter body sprite (in-match body).
  final String bodyAsset;

  /// The pack this binding came from ('omnimod.base.reference-male-01', ...).
  final String packId;

  const FighterSpriteBinding({
    required this.portraitAsset,
    required this.bodyAsset,
    required this.packId,
  });

  @override
  bool operator ==(Object other) =>
      other is FighterSpriteBinding &&
      other.portraitAsset == portraitAsset &&
      other.bodyAsset == bodyAsset &&
      other.packId == packId;

  @override
  int get hashCode => Object.hash(portraitAsset, bodyAsset, packId);

  @override
  String toString() => 'FighterSpriteBinding($packId)';
}

/// Who a fighter is: identity, stats, palette and special. Immutable.
class FighterDef {
  final String id;
  final String name;

  /// Lowercase sign id ('aries'..'pisces', or 'ophiuchus' for the boss).
  final String sign;

  /// 'fire' | 'earth' | 'air' | 'water' | 'all' (boss).
  final String element;
  final String archetype;
  final FighterStats stats;

  /// ARGB primary colour.
  final int primary;
  final List<String> temperament;

  /// Special id from specials.dart ('flare_rush', ...; 'all' for the boss).
  final String specialId;

  /// 'offline' | 'omnimind' | 'lpe' | 'plaza'
  final String source;
  final List<FighterLayer> layers;

  /// Extra display facts (handle, aura tier) for LPE / plaza fighters.
  final String? handle;
  final String? auraTier;

  /// Pack sprite binding for the default-Halo templates (and LPE fighters
  /// wearing one). Null = painted fighter.
  final FighterSpriteBinding? sprite;

  const FighterDef({
    required this.id,
    required this.name,
    required this.sign,
    required this.element,
    required this.archetype,
    required this.stats,
    required this.primary,
    required this.temperament,
    required this.specialId,
    required this.source,
    this.layers = const [],
    this.handle,
    this.auraTier,
    this.sprite,
  });

  bool get isBoss => specialId == 'all';

  String get signTitle =>
      sign.isEmpty ? sign : sign[0].toUpperCase() + sign.substring(1);

  FighterDef copyWith({
    String? id,
    String? name,
    String? source,
    int? primary,
    String? handle,
    String? auraTier,
    List<FighterLayer>? layers,
    FighterStats? stats,
    List<String>? temperament,
    FighterSpriteBinding? sprite,
    bool clearSprite = false,
  }) => FighterDef(
    id: id ?? this.id,
    name: name ?? this.name,
    sign: sign,
    element: element,
    archetype: archetype,
    stats: stats ?? this.stats,
    primary: primary ?? this.primary,
    temperament: temperament ?? this.temperament,
    specialId: specialId,
    source: source ?? this.source,
    layers: layers ?? this.layers,
    handle: handle ?? this.handle,
    auraTier: auraTier ?? this.auraTier,
    sprite: clearSprite ? null : (sprite ?? this.sprite),
  );
}

enum FighterAction {
  idle,
  walk,
  jump,
  light,
  heavy,
  block,
  special,
  hitstun,
  ko,
}

/// Mutable per-tick state of one fighter. Only MatchEngine writes it; everyone else reads.
class FighterState {
  final FighterDef def;

  /// Centre x in arena px (0..MatchEngine.arenaWidth).
  double x;

  /// Height above the ground in px (0 = standing).
  double y;

  /// Vertical velocity (px per tick, up is positive).
  double vy = 0;

  /// Horizontal velocity while airborne.
  double vx = 0;

  int hp;
  int meter = 0;
  FighterAction action = FighterAction.idle;

  /// Frames spent in the current [action].
  int actionFrames = 0;
  bool facingRight;

  /// True while a block is up (after its 2-frame startup, before release).
  bool blocking = false;
  int stunFrames = 0;

  // --- engine bookkeeping (part of the deterministic state) ---
  /// Light attacks in the current chain (max 3).
  int chain = 0;

  /// Hits the current move has landed (single-hit moves stop at 1; Flare Rush at 3).
  int moveHits = 0;

  /// Frame of the last hit the current move landed (for Flare Rush spacing).
  int lastHitFrame = -100;

  /// Landing lag / block-release frames left, during which no new action starts.
  int lag = 0;

  /// Engine frames of the last 3 blocked hits (guard break window).
  final List<int> blockedAt = [];

  /// Boss only: which of the four specials the next special uses.
  int specialCursor = 0;

  /// The special currently running ('' when none).
  String activeSpecial = '';

  /// True when the current attack started in the air.
  bool airAttack = false;

  /// Previous tick's raw intent bits (for rising-edge detection).
  int prevBits = 0;

  /// Buffered button presses (light/heavy/special/up) and how many frames they stay buffered.
  int bufBits = 0;
  int bufFrames = 0;

  // --- match summary counters ---
  int hitsLanded = 0;
  int hitsBlocked = 0;
  int specialsUsed = 0;
  int guardBreaks = 0;
  int damageDealt = 0;

  FighterState(this.def, {required this.x, required this.facingRight})
    : y = 0,
      hp = def.stats.maxHp;

  int get maxHp => def.stats.maxHp;
  bool get grounded => y <= 0;
  bool get isKo => action == FighterAction.ko;
  double get hpFraction => maxHp == 0 ? 0 : hp / maxHp;

  bool get isAttacking =>
      action == FighterAction.light ||
      action == FighterAction.heavy ||
      action == FighterAction.special;

  /// Resets position, HP and per-round state for a new round. Meter and match counters carry over.
  void resetForRound({required double x, required bool facingRight}) {
    this.x = x;
    this.facingRight = facingRight;
    y = 0;
    vy = 0;
    vx = 0;
    hp = maxHp;
    action = FighterAction.idle;
    actionFrames = 0;
    blocking = false;
    stunFrames = 0;
    chain = 0;
    moveHits = 0;
    lastHitFrame = -100;
    lag = 0;
    blockedAt.clear();
    activeSpecial = '';
    airAttack = false;
    prevBits = 0;
    bufBits = 0;
    bufFrames = 0;
  }
}
