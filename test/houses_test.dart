// Houses subclass layer (pure Dart): assignment, stat nudges, temperament
// shading and the taunt tint, over the offline zodiac roster.
import 'package:test/test.dart';

import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/npc/houses.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';

void main() {
  group('assignment', () {
    test('all 12 houses exist, numbered 1..12 in order', () {
      expect(zodiacHouses.length, 12);
      for (var i = 0; i < 12; i++) {
        expect(zodiacHouses[i].number, i + 1);
      }
    });

    test('every zodiac sign wears a house; the boss wears none', () {
      for (final sign in zodiacSigns) {
        expect(houseOf(sign), isNotNull, reason: sign);
      }
      expect(houseOf('ophiuchus'), isNull);
      expect(houseOf('not-a-sign'), isNull);
    });

    test('each house nudges exactly one stat up and a different one down', () {
      for (final h in zodiacHouses) {
        expect(h.up, isNot(h.down), reason: h.id);
      }
    });

    test('no house shade repeats a temperament word of any sign or the boss',
        () {
      final words = <String>{
        for (final z in zodiacTable.values) ...z.temperament,
        ...bossFighter().temperament,
      };
      for (final h in zodiacHouses) {
        expect(words.contains(h.shade), isFalse, reason: h.id);
      }
    });
  });

  group('stat nudges', () {
    test('apply over the sign base: +1 up, -1 down, others untouched', () {
      final aries = offlineFighter('aries')!;
      final base = zodiacTable['aries']!.stats;
      // First House: power up, wit down.
      expect(aries.stats.power, base.power + 1);
      expect(aries.stats.wit, base.wit - 1);
      expect(aries.stats.agility, base.agility);
      expect(aries.stats.resolve, base.resolve);
    });

    test('every roster fighter keeps effective stats inside 1..10', () {
      for (final f in offlineRoster()) {
        for (final v in f.stats.toList()) {
          expect(v, inInclusiveRange(1, 10), reason: f.sign);
        }
      }
    });

    test('nudges clamp at the scale edges', () {
      const top = FighterStats(power: 10, agility: 5, wit: 1, resolve: 5);
      final first = houseOf('aries')!; // power up, wit down
      final out = statsWithHouse(top, first);
      expect(out.power, 10);
      expect(out.wit, 1);
    });

    test('the engine sees the house: max HP and damage follow the nudge', () {
      // Capricorn wears the Tenth House (resolve up): more HP than its base.
      final cap = offlineFighter('capricorn')!;
      final base = zodiacTable['capricorn']!.stats;
      expect(cap.stats.resolve, base.resolve + 1);
      expect(cap.stats.maxHp, 90 + (base.resolve + 1) * 2);
      final state = FighterState(cap, x: 0, facingRight: true);
      expect(state.hp, cap.stats.maxHp);
    });
  });

  group('personality shading', () {
    test('the house shade is appended last to the sign temperament', () {
      for (final sign in zodiacSigns) {
        final f = offlineFighter(sign)!;
        final house = houseOf(sign)!;
        expect(f.temperament.last, house.shade, reason: sign);
        expect(
          f.temperament.sublist(0, f.temperament.length - 1),
          zodiacTable[sign]!.temperament,
          reason: sign,
        );
      }
    });

    test('the taunt is the sign line tinted with the house line', () {
      final leo = offlineFighter('leo')!;
      final taunt = tauntFor(leo);
      expect(taunt, contains('Kneel before the champion.'));
      expect(taunt, contains('The crowd came to see me, not you.'));
    });

    test('the boss taunt is unchanged (no house)', () {
      expect(
        tauntFor(bossFighter()),
        'Thirteen signs. You are only one.',
      );
    });

    test('applyHouse leaves a houseless def untouched', () {
      final boss = bossFighter();
      expect(identical(applyHouse(boss), boss), isTrue);
    });
  });

  group('roster shape', () {
    test('houses are a layer, not new fighters: the roster stays 12', () {
      expect(offlineRoster().length, 12);
    });

    test('manifest fighters wear their house over the manifest stats', () {
      final f = fighterFromManifest({
        'name': 'Test Shade',
        'manifest_hash': 'abcdef0123456789',
        'traits': {
          'sign': 'virgo',
          'element': 'earth',
          'archetype': 'artificer',
          'stats': {'power': 4, 'agility': 6, 'wit': 9, 'resolve': 6},
          'temperament': ['precise', 'modest', 'critical'],
        },
        'layers': const [],
      })!;
      // Sixth House: wit up (clamped at 10), power down.
      expect(f.stats.wit, 10);
      expect(f.stats.power, 3);
      expect(f.temperament.last, 'methodical');
    });
  });
}
