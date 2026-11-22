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
