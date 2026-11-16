// HOUSES — a subclass layer over the 12 zodiac signs (Kiro's ruling, Nov 13:
// BOTH stats and personality, lightly; the sign stays dominant). Pure Dart.
// Real: each of the 12 astrological houses nudges one stat +1 and another -1
// on the 1..10 scale (applied over the sign's base stats, clamped back into
// range by FighterStats.clamped) and shades the fighter's temperament with
// one house word, which also tints the VS taunt (see tauntFor). Houses are a
// layer, not new fighters: the roster stays the 12 signs, and the engine
// only ever sees the effective stats on the FighterDef it already consumes.
import '../game/fighter.dart';

/// One astrological house: its traditional domain, the stat it raises, the
/// stat it costs, and the temperament word it shades in.
class ZodiacHouse {
  /// 1..12, astrological order.
  final int number;
  final String id;
  final String title;

  /// The house's traditional domain ('Self', 'Resources', ...).
  final String domain;

  /// Stat keys ('power' | 'agility' | 'wit' | 'resolve') nudged +1 / -1.
  final String up;
  final String down;

  /// Temperament word appended to the sign's temperament (the shading).
  final String shade;

  const ZodiacHouse(
    this.number,
    this.id,
    this.title,
    this.domain,
    this.up,
    this.down,
    this.shade,
  );
}

/// The 12 houses, astrological order.
const List<ZodiacHouse> zodiacHouses = [
  ZodiacHouse(1, 'first', 'First House', 'Self', 'power', 'wit', 'assertive'),
  ZodiacHouse(2, 'second', 'Second House', 'Resources', 'resolve', 'agility', 'grounded'),
  ZodiacHouse(3, 'third', 'Third House', 'Mind', 'wit', 'resolve', 'questioning'),
  ZodiacHouse(4, 'fourth', 'Fourth House', 'Roots', 'resolve', 'power', 'protective'),
  ZodiacHouse(5, 'fifth', 'Fifth House', 'Pleasure', 'power', 'resolve', 'radiant'),
  ZodiacHouse(6, 'sixth', 'Sixth House', 'Craft', 'wit', 'power', 'methodical'),
  ZodiacHouse(7, 'seventh', 'Seventh House', 'Bonds', 'agility', 'power', 'gracious'),
  ZodiacHouse(8, 'eighth', 'Eighth House', 'Depths', 'power', 'agility', 'brooding'),
  ZodiacHouse(9, 'ninth', 'Ninth House', 'Horizons', 'agility', 'resolve', 'wandering'),
  ZodiacHouse(10, 'tenth', 'Tenth House', 'Ambition', 'resolve', 'wit', 'driven'),
  ZodiacHouse(11, 'eleventh', 'Eleventh House', 'Visions', 'wit', 'agility', 'visionary'),
  ZodiacHouse(12, 'twelfth', 'Twelfth House', 'Dreams', 'wit', 'power', 'ethereal'),
];

final Map<String, ZodiacHouse> _houseById = {
  for (final h in zodiacHouses) h.id: h,
};

/// The house worn by each sign in this slice: every sign takes the house of
/// its own number (Aries the First, Taurus the Second, ... Pisces the
/// Twelfth) — the house whose ruler the sign traditionally carries. Draft
/// pairing, listed in the PR for Kiro's later ruling. Each house's shade is
/// deliberately NOT one of the sign's own temperament words: the shading
/// deepens the trait instead of repeating it, and applyHouse leaves it last
/// in the list, where the dossier and taunt read the house from.
const Map<String, String> houseForSign = {
  'aries': 'first',
  'taurus': 'second',
  'gemini': 'third',
  'cancer': 'fourth',
  'leo': 'fifth',
  'virgo': 'sixth',
  'libra': 'seventh',
  'scorpio': 'eighth',
  'sagittarius': 'ninth',
  'capricorn': 'tenth',
  'aquarius': 'eleventh',
  'pisces': 'twelfth',
};

/// The house assigned to [sign], or null for a non-zodiac sign (the boss).
ZodiacHouse? houseOf(String sign) {
  final id = houseForSign[sign.trim().toLowerCase()];
  return id == null ? null : _houseById[id];
}

int _nudged(FighterStats s, String stat, String up, String down) {
  final v = switch (stat) {
    'power' => s.power,
    'agility' => s.agility,
    'wit' => s.wit,
    _ => s.resolve,
  };
  return v + (stat == up ? 1 : 0) - (stat == down ? 1 : 0);
}

/// [base] with [house]'s nudge applied, clamped into the 1..10 scale.
FighterStats statsWithHouse(FighterStats base, ZodiacHouse house) => FighterStats(
  power: _nudged(base, 'power', house.up, house.down),
  agility: _nudged(base, 'agility', house.up, house.down),
  wit: _nudged(base, 'wit', house.up, house.down),
  resolve: _nudged(base, 'resolve', house.up, house.down),
).clamped();

/// [def] wearing its sign's house: effective (house-adjusted) stats and the
/// sign's temperament shaded by the house word. A def whose sign has no
/// house (the boss, plaza personas) comes back unchanged.
FighterDef applyHouse(FighterDef def) {
  final house = houseOf(def.sign);
  if (house == null) return def;
  return def.copyWith(
    stats: statsWithHouse(def.stats, house),
    temperament: [...def.temperament, house.shade],
  );
}
