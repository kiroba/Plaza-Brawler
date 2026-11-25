/// Fight stages (Kiro, Nov 22, 2026): painted backdrops behind the
/// arena, replacing the placeholder gradient. Cosmetic only — the
/// choice is derived from the two fighters and the match seed, never
/// enters the state hash, and both PvP sides derive the same stage
/// from the same inputs, so they see one arena.
class Stages {
  static const plazaDawn = 'assets/stages/plaza_dawn.jpg';
  static const plazaDusk = 'assets/stages/plaza_dusk.jpg';
  static const plazaNight = 'assets/stages/plaza_night.jpg';
  static const fireArena = 'assets/stages/fire_arena.jpg';
  static const waterArena = 'assets/stages/water_arena.jpg';

  /// Looping animated twin of each still (assets/stages/<name>.webp,
  /// 12 frames). The painter plays the loop from the fight ticker; the
  /// JPG stays as the fallback when the animated asset fails to load.
  static const plazaDawnAnimated = 'assets/stages/plaza_dawn.webp';
  static const plazaDuskAnimated = 'assets/stages/plaza_dusk.webp';
  static const plazaNightAnimated = 'assets/stages/plaza_night.webp';
  static const fireArenaAnimated = 'assets/stages/fire_arena.webp';
  static const waterArenaAnimated = 'assets/stages/water_arena.webp';

  static const animatedAll = [
    plazaDawnAnimated,
    plazaDuskAnimated,
    plazaNightAnimated,
    fireArenaAnimated,
    waterArenaAnimated,
  ];

  /// The animated twin of a still stage path. Unknown paths pass through
  /// unchanged, so a still with no animated twin still loads as before.
  static String animatedFor(String still) {
    switch (still) {
      case plazaDawn:
        return plazaDawnAnimated;
      case plazaDusk:
        return plazaDuskAnimated;
      case plazaNight:
        return plazaNightAnimated;
      case fireArena:
        return fireArenaAnimated;
      case waterArena:
        return waterArenaAnimated;
      default:
        return still;
    }
  }

  /// The plaza set, in rotation order.
  static const plazas = [plazaDawn, plazaDusk, plazaNight];

  static const all = [plazaDawn, plazaDusk, plazaNight, fireArena, waterArena];

  /// An element with an arena owns the stage when it is the only one
  /// of the two present: a lone fire fighter fights in the fire
  /// arena, a lone water fighter in the water arena. Fire against
  /// water — and every other pairing — meets on neutral ground: the
  /// plaza, rotating dawn → dusk → night by seed.
  static String forMatch({
    required String p1Element,
    required String p2Element,
    required int seed,
  }) {
    final fire = p1Element == 'fire' || p2Element == 'fire';
    final water = p1Element == 'water' || p2Element == 'water';
    if (fire && !water) return fireArena;
    if (water && !fire) return waterArena;
    return plazas[seed.abs() % plazas.length];
  }
}
