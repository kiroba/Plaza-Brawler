// The element specials (spec 4.3), one set per element, shared by its three signs. Pure Dart.
// S1–S3 shipped the four NEUTRAL specials; S4 (Nov 16, 2026) adds the directional set the
// control-scheme design ruled: special + a held direction at press (forward = toward the
// opponent, back = away, down = crouch held) is a different ability — sixteen in all.
// The boss ('all') cycles elements AND directions through all sixteen.
// Quake Stomp reading of "can't be blocked while jumping": the shockwave also hits airborne
// fighters (up to 120 px high) and an airborne fighter can't block; grounded blockers still
// block it (chip).
import 'moves.dart';

enum SpecialKind {
  dashMultiHit,
  shockwave,
  teleportHeavy,
  projectilePull,
  leapStrike,
  dashBackBurst,
  bulwark,
  groundCrack,
  teleportStrike2,
  teleportEscape,
  teleportDrop,
  zone,
}

class SpecialDef {
  final String id;
  final String name;
  final String element;

  /// The direction that selects this special: 'neutral', 'forward', 'back', 'down'.
  final String dir;
  final SpecialKind kind;
  final MoveData move;

  /// Dash specials: distance covered over the active frames.
  final double dashDistance;

  /// Multi-hit specials: frames between their hits.
  final int hitSpacing;

  /// Projectile specials: speed (px per tick), lifetime (ticks) and pull on hit (px toward the caster).
  final double projectileSpeed;
  final int projectileLife;
  final double pull;

  const SpecialDef({
    required this.id,
    required this.name,
    required this.element,
    required this.kind,
    required this.move,
    this.dir = 'neutral',
    this.dashDistance = 0,
    this.hitSpacing = 0,
    this.projectileSpeed = 0,
    this.projectileLife = 0,
    this.pull = 0,
  });
}

class Specials {
  Specials._();

  /// Frames between Flare Rush's hits.
  static const flareRushHitSpacing = 2;

  // ----- FIRE -----

  /// Fire neutral: dash 140 px with a multi-hit, 3 hits of 8.
  static const flareRush = SpecialDef(
    id: 'flare_rush',
    name: 'Flare Rush',
    element: 'fire',
    kind: SpecialKind.dashMultiHit,
    move: MoveData(
      id: 'flare_rush',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 8,
      range: 60,
      knockback: 6,
      reachUp: 50,
      maxHits: 3,
    ),
    dashDistance: 140,
    hitSpacing: flareRushHitSpacing,
  );

  /// Fire forward: leaping overhead strike, single hit 26, startup 18.
  static const blazeArc = SpecialDef(
    id: 'blaze_arc',
    name: 'Blaze Arc',
    element: 'fire',
    dir: 'forward',
    kind: SpecialKind.leapStrike,
    move: MoveData(
      id: 'blaze_arc',
      startup: 18,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 26,
      range: 75,
      knockback: 10,
      reachUp: 70,
      height: HitHeight.overhead,
    ),
  );

  /// Fire back: dash back 120, fire burst left behind at the start point, 14 dmg.
  static const backdraft = SpecialDef(
    id: 'backdraft',
    name: 'Backdraft',
    element: 'fire',
    dir: 'back',
    kind: SpecialKind.dashBackBurst,
    move: MoveData(
      id: 'backdraft',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 14,
      range: 55,
      knockback: 8,
      reachUp: 60,
    ),
    projectileLife: 20,
  );

  /// Fire down: ground flame fan, 70 range, 18 dmg, +6 hitstun — the combo-starter special.
  static const scorchFan = SpecialDef(
    id: 'scorch_fan',
    name: 'Scorch Fan',
    element: 'fire',
    dir: 'down',
    kind: SpecialKind.shockwave,
    move: MoveData(
      id: 'scorch_fan',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 18,
      range: 70,
      knockback: 6,
      reachUp: 20,
      stunBonus: 6,
    ),
  );

  // ----- EARTH -----

  /// Earth neutral: ground shockwave, 90 px, also hits jumpers.
  static const quakeStomp = SpecialDef(
    id: 'quake_stomp',
    name: 'Quake Stomp',
    element: 'earth',
    kind: SpecialKind.shockwave,
    move: MoveData(
      id: 'quake_stomp',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: Moves.specialDamage,
      range: 90,
      knockback: 12,
      reachUp: 120,
    ),
  );

  /// Earth forward: shoulder-charge dash 100, 24 dmg, knockback 18, counts as
  /// 2 hits toward guard break.
  static const landslide = SpecialDef(
    id: 'landslide',
    name: 'Landslide',
    element: 'earth',
    dir: 'forward',
    kind: SpecialKind.dashMultiHit,
    move: MoveData(
      id: 'landslide',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 24,
      range: 70,
      knockback: 18,
      reachUp: 50,
      guardWeight: 2,
    ),
    dashDistance: 100,
  );

  /// Earth back: reinforced guard 30 frames — no chip, no guard-break
  /// accumulation. Costs the full bar like every special. The activation
  /// itself is quick (8/2/10) so the caster can actually block inside the
  /// window — the design's flagged tuning question, answered this way.
  static const bulwark = SpecialDef(
    id: 'bulwark',
    name: 'Bulwark',
    element: 'earth',
    dir: 'back',
    kind: SpecialKind.bulwark,
    move: MoveData(
      id: 'bulwark',
      startup: 8,
      active: 2,
      recovery: 10,
      damage: 0,
      range: 1,
    ),
  );

  /// Earth down: crack travels the ground 160 px at 5 px/tick, 20 dmg, a low;
  /// whiffs airborne completely.
  static const fissure = SpecialDef(
    id: 'fissure',
    name: 'Fissure',
    element: 'earth',
    dir: 'down',
    kind: SpecialKind.groundCrack,
    move: MoveData(
      id: 'fissure',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 20,
      range: 24,
      knockback: 8,
      reachUp: 10,
      height: HitHeight.low,
    ),
    projectileSpeed: 5,
    projectileLife: 32,
  );

  // ----- AIR -----

  /// Air neutral: teleport behind the opponent, then a heavy.
  static const galeStep = SpecialDef(
    id: 'gale_step',
    name: 'Gale Step',
    element: 'air',
    kind: SpecialKind.teleportHeavy,
    move: MoveData(
      id: 'gale_step',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: Moves.specialDamage,
      range: 85,
      knockback: 20,
      reachUp: 70,
    ),
  );

  /// Air forward: teleport strike in front (12), again from behind (12).
  static const crosswind = SpecialDef(
    id: 'crosswind',
    name: 'Crosswind',
    element: 'air',
    dir: 'forward',
    kind: SpecialKind.teleportStrike2,
    move: MoveData(
      id: 'crosswind',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 12,
      range: 75,
      knockback: 10,
      reachUp: 70,
      maxHits: 2,
    ),
    hitSpacing: 6,
  );

  /// Air back: teleport to max range away, refunds 20 meter (net cost 80). Pure escape.
  static const slipstream = SpecialDef(
    id: 'slipstream',
    name: 'Slipstream',
    element: 'air',
    dir: 'back',
    kind: SpecialKind.teleportEscape,
    move: MoveData(
      id: 'slipstream',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 0,
      range: 1,
    ),
  );

  /// Air down: teleport above the opponent, dropping strike 24. An overhead.
  static const downburst = SpecialDef(
    id: 'downburst',
    name: 'Downburst',
    element: 'air',
    dir: 'down',
    kind: SpecialKind.teleportDrop,
    move: MoveData(
      id: 'downburst',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 24,
      range: 70,
      knockback: 12,
      reachUp: 70,
      height: HitHeight.overhead,
    ),
  );

  // ----- WATER -----

  /// Water neutral: projectile that pulls the opponent 60 px toward the caster.
  static const undertow = SpecialDef(
    id: 'undertow',
    name: 'Undertow',
    element: 'water',
    kind: SpecialKind.projectilePull,
    move: MoveData(
      id: 'undertow',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: Moves.specialDamage,
      range: 24,
      reachUp: 60,
    ),
    projectileSpeed: 7,
    projectileLife: 60,
    pull: 60,
  );

  /// Water forward: faster projectile (9 px/tick), pull 100, 16 dmg. Less
  /// damage, far more control.
  static const riptide = SpecialDef(
    id: 'riptide',
    name: 'Riptide',
    element: 'water',
    dir: 'forward',
    kind: SpecialKind.projectilePull,
    move: MoveData(
      id: 'riptide',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 16,
      range: 24,
      reachUp: 60,
    ),
    projectileSpeed: 9,
    projectileLife: 60,
    pull: 100,
  );

  /// Water back: short wave, pushes the opponent 120 away, 10 dmg, recovery 16
  /// (the safest special in the game). Space-maker.
  static const ebb = SpecialDef(
    id: 'ebb',
    name: 'Ebb',
    element: 'water',
    dir: 'back',
    kind: SpecialKind.projectilePull,
    move: MoveData(
      id: 'ebb',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: 16,
      damage: 10,
      range: 24,
      knockback: 120,
      reachUp: 60,
    ),
    projectileSpeed: 6,
    projectileLife: 20,
  );

  /// Water down: 50-radius zone at the caster's feet for 30 frames, drags the
  /// opponent in at 3 px/tick, ends in a 14-dmg burst.
  static const whirlpool = SpecialDef(
    id: 'whirlpool',
    name: 'Whirlpool',
    element: 'water',
    dir: 'down',
    kind: SpecialKind.zone,
    move: MoveData(
      id: 'whirlpool',
      startup: Moves.specialStartup,
      active: Moves.specialActive,
      recovery: Moves.specialRecovery,
      damage: 14,
      range: 50,
      knockback: 10,
      reachUp: 30,
    ),
  );

  /// The four neutral specials (the pre-S4 registry).
  static const all = [flareRush, quakeStomp, galeStep, undertow];

  /// The twelve directional specials.
  static const directionals = [
    blazeArc,
    backdraft,
    scorchFan,
    landslide,
    bulwark,
    fissure,
    crosswind,
    slipstream,
    downburst,
    riptide,
    ebb,
    whirlpool,
  ];

  /// All sixteen specials.
  static const allDefs = [...all, ...directionals];

  /// The boss's cycle: element-major, direction fastest — all sixteen.
  static const bossCycle = [
    flareRush,
    blazeArc,
    backdraft,
    scorchFan,
    quakeStomp,
    landslide,
    bulwark,
    fissure,
    galeStep,
    crosswind,
    slipstream,
    downburst,
    undertow,
    riptide,
    ebb,
    whirlpool,
  ];

  static SpecialDef byId(String id) {
    for (final s in allDefs) {
      if (s.id == id) return s;
    }
    return flareRush;
  }

  static SpecialDef forElement(String element) {
    for (final s in all) {
      if (s.element == element) return s;
    }
    return flareRush;
  }

  /// The special for [element] + [dir] ('neutral', 'forward', 'back', 'down').
  static SpecialDef directional(String element, String dir) {
    if (dir == 'neutral') return forElement(element);
    for (final s in directionals) {
      if (s.element == element && s.dir == dir) return s;
    }
    return forElement(element);
  }

  /// Special id for an element ('all' for the boss).
  static String idForElement(String element) =>
      element == 'all' ? 'all' : forElement(element).id;

  /// Presentation colour (ARGB) per element — banners, projectile and spark tints.
  static int colorOf(String element) => switch (element) {
    'fire' => 0xFFFF7043,
    'earth' => 0xFFFFB300,
    'air' => 0xFFB2EBF2,
    'water' => 0xFF4CC9F0,
    'all' => 0xFFFFD54F,
    _ => 0xFFFFFFFF,
  };
}
