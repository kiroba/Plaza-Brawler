// Secret fighters (Slice 2): the creepy man def, the boss-win gate, and the
// arcade ladder for a secret player. Pure Dart.
import 'dart:convert';
import 'dart:io';

import 'package:plaza_brawler/game/arcade.dart';
import 'package:plaza_brawler/game/specials.dart';
import 'package:plaza_brawler/net/pack_fighter.dart';
import 'package:plaza_brawler/npc/secret_fighters.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

void main() {
  group('creepyManFighter', () {
    test('is the realistic figure, not a painted zodiac fighter', () {
      final f = creepyManFighter();
      expect(f.sign, creepyManSign);
      expect(f.name, 'The Creepy Man');
      expect(f.source, 'secret');
      expect(f.isBoss, isFalse);
      // The bundled male pack's own binding — the same one
      // bindingFromManifest derives from that pack's manifest.
      final manifest =
          jsonDecode(
                File(
                  'assets/packs/omnimod.base.reference-male-01/manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        f.sprite,
        bindingFromManifest(
          manifest,
          packId: 'omnimod.base.reference-male-01',
        ),
      );
      // A real water special (not the boss 'all'), stats below the boss 9s.
      expect(Specials.byId(f.specialId).element, 'water');
      for (final v in f.stats.toList()) {
        expect(v, inInclusiveRange(1, 10));
      }
      expect(f.stats.power, lessThan(9));
    });

    test('is not a zodiac sign and never the boss', () {
      final f = creepyManFighter();
      expect(zodiacSigns, isNot(contains(f.sign)));
      expect(f.sign, isNot('ophiuchus'));
      expect(offlineFighter(f.sign), isNull);
      expect(offlineRoster().map((d) => d.sign), isNot(contains(f.sign)));
    });
  });

  group('the gate', () {
    test('locked until the boss win, open after it', () {
      final f = creepyManFighter();
      expect(isSecretFighter(f), isTrue);
      expect(isSecretLocked(f, bossBeaten: false), isTrue);
      expect(isSecretLocked(f, bossBeaten: true), isFalse);
      expect(
        isSecretLocked(offlineFighter('aries')!, bossBeaten: false),
        isFalse,
      );
    });

    test('player roster is 12 signs + the creepy man last', () {
      final roster = playerRoster();
      expect(roster.length, 13);
      expect(roster.last.sign, creepyManSign);
      expect(roster.take(12).map((d) => d.sign), zodiacSigns);
    });

    test('the opponent roster never holds the secret fighter', () {
      final opponents = [...offlineRoster(), bossFighter()];
      expect(opponents.any(isSecretFighter), isFalse);
    });
  });

  group('arcade ladder for a secret player', () {
    test('11 zodiac signs + the Ophiuchus boss, boss win is a win', () {
      final run = ArcadeRun(seed: 7, player: creepyManFighter());
      expect(run.length, 12);
      expect(run.ladder.last, 'ophiuchus');
      expect(run.ladder.take(11).toSet().length, 11);
      expect(run.ladder.take(11).every(zodiacSigns.contains), isTrue);
      run.index = run.length - 1;
      expect(run.atBoss, isTrue);
      expect(run.onFightEnd(playerWon: true), RunStatus.won);
    });
  });
}
