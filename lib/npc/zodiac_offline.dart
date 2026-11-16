// Offline zodiac fighters (spec 5.2). Pure Dart.
// Real: the same 12-sign table as the daemon's OmniMind zodiac generator (Admin/omni_omnimind.py ZODIAC):
// element, modality, archetype, temperament, base colour and base stats, plus the Ophiuchus boss.
// Offline fighters use base stats with no seed nudges and a fixed name ("Shade of Scorpio"); the daemon's
// seeded names and layer picks come from OmniMind when the node is there (lib/net/omnimind_client.dart).
import '../game/fighter.dart';
import '../game/specials.dart';
import 'houses.dart';

class ZodiacSign {
  final String sign;
  final String element;
  final String modality;
  final String archetype;
  final List<String> temperament;
  final String baseHex;
  final FighterStats stats;

  const ZodiacSign(
    this.sign,
    this.element,
    this.modality,
    this.archetype,
    this.temperament,
    this.baseHex,
    this.stats,
  );

  String get title => sign[0].toUpperCase() + sign.substring(1);
}

/// Daemon order (ZODIAC_SIGNS).
const List<String> zodiacSigns = [
  'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo', //
  'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
];

const Map<String, ZodiacSign> zodiacTable = {
  'aries': ZodiacSign(
    'aries',
    'fire',
    'cardinal',
    'vanguard',
    ['bold', 'restless', 'direct'],
    '#d7263d',
    FighterStats(power: 8, agility: 7, wit: 4, resolve: 6),
  ),
  'taurus': ZodiacSign(
    'taurus',
    'earth',
    'fixed',
    'warden',
    ['steady', 'patient', 'stubborn'],
    '#6a994e',
    FighterStats(power: 7, agility: 3, wit: 5, resolve: 9),
  ),
  'gemini': ZodiacSign(
    'gemini',
    'air',
    'mutable',
    'trickster',
    ['curious', 'witty', 'fickle'],
    '#f4d35e',
    FighterStats(power: 4, agility: 7, wit: 9, resolve: 3),
  ),
  'cancer': ZodiacSign(
    'cancer',
    'water',
    'cardinal',
    'keeper',
    ['loyal', 'guarded', 'tender'],
    '#9fb8ad',
    FighterStats(power: 5, agility: 4, wit: 6, resolve: 8),
  ),
  'leo': ZodiacSign(
    'leo',
    'fire',
    'fixed',
    'champion',
    ['proud', 'generous', 'dramatic'],
    '#f19c1f',
    FighterStats(power: 8, agility: 5, wit: 5, resolve: 7),
  ),
  'virgo': ZodiacSign(
    'virgo',
    'earth',
    'mutable',
    'artificer',
    ['precise', 'modest', 'critical'],
    '#8d7b68',
    FighterStats(power: 4, agility: 6, wit: 9, resolve: 6),
  ),
  'libra': ZodiacSign(
    'libra',
    'air',
    'cardinal',
    'envoy',
    ['fair', 'charming', 'indecisive'],
    '#e8a0bf',
    FighterStats(power: 4, agility: 6, wit: 8, resolve: 5),
  ),
  'scorpio': ZodiacSign(
    'scorpio',
    'water',
    'fixed',
    'shade',
    ['intense', 'secretive', 'relentless'],
    '#5c1a33',
    FighterStats(power: 7, agility: 6, wit: 7, resolve: 8),
  ),
  'sagittarius': ZodiacSign(
    'sagittarius',
    'fire',
    'mutable',
    'ranger',
    ['free', 'blunt', 'hopeful'],
    '#7b2cbf',
    FighterStats(power: 6, agility: 9, wit: 6, resolve: 5),
  ),
  'capricorn': ZodiacSign(
    'capricorn',
    'earth',
    'cardinal',
    'strategist',
    ['disciplined', 'dry', 'ambitious'],
    '#3d405b',
    FighterStats(power: 6, agility: 4, wit: 8, resolve: 9),
  ),
  'aquarius': ZodiacSign(
    'aquarius',
    'air',
    'fixed',
    'visionary',
    ['inventive', 'aloof', 'humane'],
    '#2ec4b6',
    FighterStats(power: 4, agility: 5, wit: 9, resolve: 6),
  ),
  'pisces': ZodiacSign(
    'pisces',
    'water',
    'mutable',
    'mystic',
    ['dreamy', 'kind', 'elusive'],
    '#5e60ce',
    FighterStats(power: 3, agility: 6, wit: 8, resolve: 6),
  ),
};

/// '#rrggbb' -> opaque ARGB int. Falls back to [fallback] for anything else.
int hexToArgb(String? hex, {int fallback = 0xFF3A86EF}) {
  final s = (hex ?? '').trim();
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s);
  if (m == null) return fallback;
  return 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

// First option of each daemon layer list (no seed): body/palette/aura by element, outfit by modality.
const _offlineBody = {
  'fire': 'body_lithe',
  'earth': 'body_stout',
  'air': 'body_lithe',
  'water': 'body_slim',
};
const _offlinePalette = {
  'fire': 'pal_ember',
  'earth': 'pal_moss',
  'air': 'pal_sky',
  'water': 'pal_tide',
};
const _offlineOutfit = {
  'cardinal': 'fit_plate',
  'fixed': 'fit_robe',
  'mutable': 'fit_leathers',
};
const _offlineAura = {
  'fire': 'aura_flare',
  'earth': 'aura_dust',
  'air': 'aura_breeze',
  'water': 'aura_ripple',
};
const _accessories = [
  'acc_horns',
  'acc_circlet',
  'acc_mask',
  'acc_lantern',
  'acc_scarf',
  'acc_bracers', //
  'acc_quiver',
  'acc_tome',
  'acc_pendant',
  'acc_goggles',
  'acc_shell',
  'acc_feather',
];

/// The fixed offline fighter for a sign (base stats, "Archetype of Sign"), or null for an unknown sign.
FighterDef? offlineFighter(String sign) {
  final key = sign.trim().toLowerCase();
  final z = zodiacTable[key];
  if (z == null) return null;
  final tint = hexToArgb(z.baseHex);
  final layers = [
    FighterLayer(
      layer: 'body',
      assetId: _offlineBody[z.element]!,
      z: 0,
      tint: tint,
    ),
    FighterLayer(
      layer: 'palette',
      assetId: _offlinePalette[z.element]!,
      z: 1,
      tint: tint,
    ),
    FighterLayer(
      layer: 'outfit',
      assetId: _offlineOutfit[z.modality]!,
      z: 2,
      tint: tint,
    ),
    FighterLayer(
      layer: 'accessory',
      assetId: _accessories[zodiacSigns.indexOf(key)],
      z: 3,
      tint: tint,
    ),
    FighterLayer(
      layer: 'aura',
      assetId: _offlineAura[z.element]!,
      z: 4,
      tint: tint,
      opacity: 80,
    ),
  ];
  final arch = z.archetype[0].toUpperCase() + z.archetype.substring(1);
  return applyHouse(FighterDef(
    id: 'offline_$key',
    name: '$arch of ${z.title}',
    sign: key,
    element: z.element,
    archetype: z.archetype,
    stats: z.stats,
    primary: tint,
    temperament: z.temperament,
    specialId: Specials.idForElement(z.element),
    source: 'offline',
    layers: layers,
  ));
}

/// All 12 offline fighters in daemon order.
List<FighterDef> offlineRoster() => [
  for (final s in zodiacSigns) offlineFighter(s)!,
];

/// "Ophiuchus, the 13th Sign": all stats 9, uses all four specials, its own palette.
FighterDef bossFighter() {
  const tint = 0xFFC9A227; // serpent gold
  const glow = 0xFF1B998B; // venom teal
  return const FighterDef(
    id: 'boss_ophiuchus',
    name: 'Ophiuchus, the 13th Sign',
    sign: 'ophiuchus',
    element: 'all',
    archetype: 'serpent',
    stats: FighterStats(power: 9, agility: 9, wit: 9, resolve: 9),
    primary: tint,
    temperament: ['relentless', 'patient', 'elusive'],
    specialId: 'all',
    source: 'offline',
    layers: [
      FighterLayer(layer: 'body', assetId: 'body_tall', z: 0, tint: tint),
      FighterLayer(layer: 'palette', assetId: 'pal_serpent', z: 1, tint: glow),
      FighterLayer(layer: 'outfit', assetId: 'fit_cloak', z: 2, tint: glow),
      FighterLayer(
        layer: 'accessory',
        assetId: 'acc_circlet',
        z: 3,
        tint: tint,
      ),
      FighterLayer(
        layer: 'aura',
        assetId: 'aura_halo',
        z: 4,
        tint: glow,
        opacity: 80,
      ),
    ],
  );
}

/// A FighterDef from a daemon generate-asset manifest, or null when the manifest is malformed.
/// Stats and layers come from the manifest (seeded on the node); special from its element.
FighterDef? fighterFromManifest(
  Map<String, dynamic> m, {
  String source = 'omnimind',
}) {
  try {
    final traits = m['traits'];
    if (traits is! Map) return null;
    final sign = (m['sign'] ?? traits['sign'] ?? '').toString().toLowerCase();
    final z = zodiacTable[sign];
    if (z == null) return null;
    final st = traits['stats'];
    if (st is! Map) return null;
    int stat(String k) => (st[k] as num).toInt();
    final stats = FighterStats(
      power: stat('power'),
      agility: stat('agility'),
      wit: stat('wit'),
      resolve: stat('resolve'),
    ).clamped();
    final element = (traits['element'] ?? z.element).toString();
    final temperament = traits['temperament'] is List
        ? [for (final t in traits['temperament'] as List) t.toString()]
        : z.temperament;
    final layers = <FighterLayer>[];
    if (m['layers'] is List) {
      for (final l in m['layers'] as List) {
        if (l is! Map) continue;
        layers.add(
          FighterLayer(
            layer: (l['layer'] ?? '').toString(),
            assetId: (l['asset_id'] ?? '').toString(),
            z: (l['z'] as num?)?.toInt() ?? layers.length,
            tint: hexToArgb(
              l['tint']?.toString(),
              fallback: hexToArgb(z.baseHex),
            ),
            opacity: (l['opacity'] as num?)?.toInt() ?? 100,
          ),
        );
      }
    }
    final name = (m['name'] ?? '').toString();
    final hash = (m['manifest_hash'] ?? '').toString();
    return applyHouse(FighterDef(
      id: 'omnimind_${sign}_${hash.length >= 8 ? hash.substring(0, 8) : (m['seed'] ?? 0)}',
      name: name.isEmpty ? offlineFighter(sign)!.name : name,
      sign: sign,
      element: element,
      archetype: (traits['archetype'] ?? z.archetype).toString(),
      stats: stats,
      primary: layers.isNotEmpty ? layers.first.tint : hexToArgb(z.baseHex),
      temperament: temperament,
      specialId: Specials.idForElement(element),
      source: source,
      layers: layers,
    ));
  } catch (_) {
    return null;
  }
}

const Map<String, String> _taunts = {
  'bold': 'Step up. I hit first.',
  'restless': "Can't stand still. Can you keep up?",
  'steady': 'You will tire before I move.',
  'patient': 'I can wait all day.',
  'curious': 'Show me a trick I have not seen.',
  'witty': 'Two of me, zero of you.',
  'loyal': 'I fight for my own. Turn back.',
  'guarded': 'My guard does not break.',
  'proud': 'Kneel before the champion.',
  'precise': 'Every flaw in your stance, counted.',
  'fair': 'May the better fighter win. That is me.',
  'intense': 'You already lost. You just do not know it.',
  'free': 'Catch me if you can.',
  'disciplined': 'Discipline beats talent.',
  'inventive': 'I built a move just for you.',
  'dreamy': 'I dreamt of this fight. You lose.',
  'relentless': 'Thirteen signs. You are only one.',
};

const Map<String, String> _houseTaunts = {
  'first': 'I am the first thing you will regret.',
  'second': 'What is mine stays mine.',
  'third': 'I have already read your next move.',
  'fourth': 'My roots do not move for you.',
  'fifth': 'The crowd came to see me, not you.',
  'sixth': 'Craft beats noise. Watch.',
  'seventh': 'Every bond I keep makes me faster.',
  'eighth': 'I have seen the deep end. You have not.',
  'ninth': 'The horizon is mine. Run if you like.',
  'tenth': 'Ambition does not blink.',
  'eleventh': 'I fight for everyone watching.',
  'twelfth': 'I dreamt this ending too.',
};

/// One-line VS splash taunt from the fighter's temperament. A zodiac fighter
/// wearing a house (the house shade sits last in its temperament) gets its
/// sign's line tinted with the house's line; unhoused fighters are unchanged.
String tauntFor(FighterDef f) {
  String? base;
  for (final t in f.temperament) {
    final line = _taunts[t];
    if (line != null) {
      base = line;
      break;
    }
  }
  base ??= 'Let us see what you have.';
  final house = houseOf(f.sign);
  if (house != null &&
      f.temperament.isNotEmpty &&
      f.temperament.last == house.shade) {
    final tint = _houseTaunts[house.id];
    if (tint != null) return '$base $tint';
  }
  return base;
}
