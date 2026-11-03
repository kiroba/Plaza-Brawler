// The four element specials (spec 4.3), one per element, shared by its three signs. Pure Dart.
// Real: frame data and behaviour flags the MatchEngine reads. The boss ('all') cycles through all four.
// Quake Stomp reading of "can't be blocked while jumping": the shockwave also hits airborne fighters
// (up to 120 px high) and an airborne fighter can't block; grounded blockers still block it (chip).
import 'moves.dart';

enum SpecialKind { dashMultiHit, shockwave, teleportHeavy, projectilePull }

class SpecialDef {
  final String id;
  final String name;
  final String element;
  final SpecialKind kind;
  final MoveData move;

  /// Flare Rush: dash distance over the active frames.
  final double dashDistance;

  /// Flare Rush: frames between its hits.
  final int hitSpacing;

  /// Undertow: projectile speed (px per tick), lifetime (ticks) and pull on hit (px toward the caster).
  final double projectileSpeed;
  final int projectileLife;
  final double pull;

  const SpecialDef({
    required this.id,
    required this.name,
    required this.element,
    required this.kind,
    required this.move,
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

  /// Fire: dash 140 px with a multi-hit, 3 hits of 8.
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

  /// Earth: ground shockwave, 90 px, also hits jumpers.
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

  /// Air: teleport behind the opponent, then a heavy.
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

  /// Water: projectile that pulls the opponent 60 px toward the caster.
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

  static const all = [flareRush, quakeStomp, galeStep, undertow];

  static SpecialDef byId(String id) {
    for (final s in all) {
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

  /// Special id for an element ('all' for the boss).
  static String idForElement(String element) =>
      element == 'all' ? 'all' : forElement(element).id;
}
