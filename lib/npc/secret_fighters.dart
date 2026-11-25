// Secret fighters (Slice 2, Nov 25, 2026): characters unlocked by beating
// the arcade boss, never in the playable roster before that. FIRST: the
// creepy man — the MakeHuman realistic figure. Rocketbox friends come later
// in intervals; they are NOT built here. Pure Dart.
// Real: the creepy man wears the bundled reference-male-01 pack binding —
// the same realistic-figure sprite path LPE fighters use (portrait +
// three-quarter body from assets/packs/...). The Mocap Set 1 bake is NOT
// wired: the arena painter draws one static body sprite posed by transform,
// so there is no animated-sprite playback path for the baked frames to plug
// into. That is a separate animated-assets slice, not faked here.
import '../game/fighter.dart';
import '../game/specials.dart';
import 'zodiac_offline.dart';

/// Sign id of the creepy man. Not a zodiac sign and not 'ophiuchus': the
/// arcade ladder (ArcadeRun.buildLadder) only ever lists zodiac signs + the
/// boss, so he can never appear as an arcade opponent, and the playable
/// roster is exactly the 12 signs until he is unlocked.
const String creepyManSign = 'creepyman';

/// The creepy man: the realistic MakeHuman figure, not a painted zodiac
/// fighter. Strong but below the boss (9s): 8/8/7/8, water special. His
/// sprite binding is the bundled male pack's own portrait + three-quarter
/// assets — the same binding bindingFromManifest derives from that pack's
/// manifest, so the def and the pack can never drift apart silently.
FighterDef creepyManFighter() {
  return FighterDef(
    id: 'secret_creepyman',
    name: 'The Creepy Man',
    sign: creepyManSign,
    element: 'water',
    archetype: 'stranger',
    stats: const FighterStats(power: 8, agility: 8, wit: 7, resolve: 8),
    primary: 0xFFC9A227, // serpent gold, shared with the boss he hides behind
    temperament: const ['quiet', 'patient', 'elusive'],
    specialId: Specials.idForElement('water'),
    source: 'secret',
    sprite: const FighterSpriteBinding(
      portraitAsset:
          'assets/packs/omnimod.base.reference-male-01/sprites/sprite_portrait_128.png',
      bodyAsset:
          'assets/packs/omnimod.base.reference-male-01/sprites/sprite_three_quarter_128.png',
      packId: 'omnimod.base.reference-male-01',
    ),
  );
}

/// True when [f] is a secret fighter (never part of the 12-sign roster).
bool isSecretFighter(FighterDef f) => f.sign == creepyManSign;

/// True when [f] is the secret fighter and the boss win hasn't unlocked him
/// yet. The gate the character-select screen reads.
bool isSecretLocked(
  FighterDef f, {
  required bool bossBeaten,
}) =>
    isSecretFighter(f) && !bossBeaten;

/// The player-mode character-select roster: the 12 signs plus the creepy
/// man last. He is always listed — locked until the boss win — so the goal
/// is visible instead of a fighter appearing out of nowhere. Opponent mode
/// never calls this: the boss stays boss-only there and the creepy man never
/// appears as an opponent.
List<FighterDef> playerRoster() => [...offlineRoster(), creepyManFighter()];
