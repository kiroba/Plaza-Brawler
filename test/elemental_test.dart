// Slice S4 (Nov 16, 2026): directional specials — special + a held direction
// picks a different ability per element (16 in all), plus the mechanics that
// are genuinely new: Bulwark's reinforced guard, Landslide's guard weight,
// Fissure's ground crack, Whirlpool's drag zone, Slipstream's refund.
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/game/moves.dart';
import 'package:plaza_brawler/game/specials.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

const _none = FighterIntent.none;
const _sp = FighterIntent(FighterIntent.special);
const _spF = FighterIntent(FighterIntent.special | FighterIntent.right);
const _spB = FighterIntent(FighterIntent.special | FighterIntent.left);
const _spD = FighterIntent(FighterIntent.special | FighterIntent.crouch);
const _block = FighterIntent(FighterIntent.block);
const _blockLow = FighterIntent(FighterIntent.block | FighterIntent.crouch);
const _hp = FighterIntent(FighterIntent.hp);

FighterDef _f(String sign) => offlineFighter(sign)!;

MatchEngine _fight(String s1, String s2, {double x1 = 200, double x2 = 248}) {
  final e = MatchEngine(p1: _f(s1), p2: _f(s2));
  for (var i = 0; i < MatchEngine.introFrames; i++) {
    e.tickWith(_none, _none);
  }
  expect(e.phase, MatchPhase.fight);
  e.p1.x = x1;
  e.p2.x = x2;
  return e;
}

int _dmg(FighterDef d, int base) => (base * d.stats.damageMultiplier).round();

void _run(MatchEngine e, int ticks, [FighterIntent a = _none, FighterIntent b = _none]) {
  for (var t = 0; t < ticks; t++) {
    e.tickWith(a, b);
  }
}

void main() {
  group('directional specials (S4)', () {
    test('special + direction selects the ability (fire set)', () {
      String pick(FighterIntent intent) {
        final e = _fight('aries', 'taurus');
        e.p1.meter = Moves.meterMax;
        e.tickWith(intent, _none);
        return e.p1.activeSpecial;
      }

      expect(pick(_sp), 'flare_rush');
      expect(pick(_spF), 'blaze_arc');
      expect(pick(_spB), 'backdraft');
      expect(pick(_spD), 'scorch_fan');
    });

    test('Blaze Arc is an overhead: crouch block fails, standing block holds', () {
      final clean = _fight('aries', 'taurus', x2: 280);
      clean.p1.meter = Moves.meterMax;
      clean.tickWith(_spF, _blockLow);
      _run(clean, 30, _none, _blockLow);
      expect(clean.p2.hp, clean.p2.maxHp - _dmg(clean.p1.def, 26));

      final blocked = _fight('aries', 'taurus', x2: 280);
      blocked.p1.meter = Moves.meterMax;
      blocked.tickWith(_spF, _block);
      _run(blocked, 30, _none, _block);
      final chip = _dmg(blocked.p1.def, 26) ~/ 5; // 20% chip, floored by the engine
      expect(blocked.p2.hp, greaterThan(blocked.p2.maxHp - _dmg(blocked.p1.def, 26)));
      expect(blocked.p2.hp, lessThanOrEqualTo(blocked.p2.maxHp - (chip > 0 ? 1 : 0)));
      expect(blocked.p1.hitsBlocked, 1);
    });

    test('Fissure is a low that whiffs airborne completely', () {
      final standing = _fight('taurus', 'aries', x2: 320);
      standing.p1.meter = Moves.meterMax;
      standing.tickWith(_spD, _block); // standing block vs a low: clean hit
      _run(standing, 45, _none, _block);
      expect(standing.p2.hp, standing.p2.maxHp - _dmg(standing.p1.def, 20));

      final low = _fight('taurus', 'aries', x2: 320);
      low.p1.meter = Moves.meterMax;
      low.tickWith(_spD, _blockLow);
      _run(low, 45, _none, _blockLow);
      expect(low.p1.hitsBlocked, 1);
      expect(low.p2.hp, greaterThan(low.p2.maxHp - _dmg(low.p1.def, 20)));

      final air = _fight('taurus', 'aries', x2: 320);
      air.p1.meter = Moves.meterMax;
      air.tickWith(_spD, _none);
      for (var t = 0; t < 55; t++) {
        if (t > 10 && t < 48) air.p2.y = 80; // held airborne while the crack passes
        air.tickWith(_none, _none);
      }
      expect(air.p2.hp, air.p2.maxHp);
    });

    test('Backdraft leaves a burst behind and retreats 120', () {
      final e = _fight('aries', 'taurus', x1: 300, x2: 345);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spB, _none);
      _run(e, 25);
      expect(e.p2.hp, e.p2.maxHp - _dmg(e.p1.def, 14));
      expect(e.p1.x, lessThanOrEqualTo(190));
    });

    test('Landslide counts as 2 toward guard break: one more blocked hit breaks', () {
      final e = _fight('taurus', 'aries', x2: 290);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spF, _block);
      _run(e, 25, _none, _block);
      expect(e.p2.blockedAt.length, 2);
      expect(e.p1.guardBreaks, 0);
      // Wait out the special, then one blocked mid (HP) is the third credit.
      // (An LP would be a low — it lands clean through a standing block.)
      var guard = 0;
      while (e.p1.action != FighterAction.idle && guard++ < 40) {
        e.tickWith(_none, _block);
      }
      e.tickWith(_hp, _block);
      _run(e, 12, _none, _block);
      expect(e.p1.guardBreaks, 1);
      expect(e.p2.action, FighterAction.hitstun);
    });

    test('Bulwark: a blocked hit inside the window deals no chip, no credit', () {
      final e = _fight('taurus', 'aries', x2: 250);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spB, _none); // Bulwark (quick 8/2/10 activation)
      _run(e, 21); // activation done ~t20, window still open
      expect(e.p1.bulwarkFrames, greaterThan(0));
      final hp0 = e.p1.hp;
      e.tickWith(_block, _hp); // P2's HP starts; P1 blocks
      _run(e, 8, _block, _none);
      expect(e.p2.hitsBlocked, 1);
      expect(e.p1.hp, hp0); // no chip under Bulwark
      expect(e.p1.blockedAt, isEmpty); // and no guard-break credit
    });

    test('Slipstream teleports to max range and refunds 20 meter', () {
      final e = _fight('gemini', 'aries', x2: 300);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spB, _none);
      _run(e, 18);
      expect(e.p1.x, MatchEngine.maxX);
      expect(e.p1.meter, 20);
    });

    test('Crosswind strikes twice: in front, then from behind', () {
      final e = _fight('gemini', 'aries', x2: 300);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spF, _none);
      _run(e, 40);
      expect(e.p1.hitsLanded, 2);
      expect(e.p2.hp, e.p2.maxHp - 2 * _dmg(e.p1.def, 12));
    });

    test('Downburst is an overhead dropped on the opponent', () {
      final e = _fight('gemini', 'aries', x2: 260);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spD, _blockLow); // crouch block cannot stop an overhead
      _run(e, 30, _none, _blockLow);
      expect(e.p2.hp, e.p2.maxHp - _dmg(e.p1.def, 24));
    });

    test('Riptide pulls 100 where Undertow pulls 60', () {
      final rip = _fight('cancer', 'aries', x2: 450);
      rip.p1.meter = Moves.meterMax;
      rip.tickWith(_spF, _none);
      _run(rip, 50);
      expect(rip.p2.hp, rip.p2.maxHp - _dmg(rip.p1.def, 16));
      expect(rip.p2.x, closeTo(350, 1));

      final und = _fight('cancer', 'aries', x2: 450);
      und.p1.meter = Moves.meterMax;
      und.tickWith(_sp, _none);
      _run(und, 55);
      expect(und.p2.x, closeTo(390, 1));
    });

    test('Whirlpool drags the opponent in and bursts at expiry', () {
      final e = _fight('cancer', 'aries', x1: 300, x2: 345);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spD, _none);
      _run(e, 35);
      expect(e.p2.x, lessThanOrEqualTo(342)); // dragged to the caster's spacing
      _run(e, 18);
      expect(e.p2.hp, e.p2.maxHp - _dmg(e.p1.def, 14));
    });

    test('Scorch Fan carries +6 hitstun', () {
      final e = _fight('aries', 'taurus', x2: 260);
      e.p1.meter = Moves.meterMax;
      e.tickWith(_spD, _none);
      var maxStun = 0;
      for (var t = 0; t < 30; t++) {
        e.tickWith(_none, _none);
        if (e.p2.stunFrames > maxStun) maxStun = e.p2.stunFrames;
      }
      expect(maxStun, Moves.specialActive + 6 + 6);
    });

    test('the boss cycles elements and directions — all sixteen', () {
      final e = MatchEngine(p1: bossFighter(), p2: _f('aries'));
      for (var i = 0; i < MatchEngine.introFrames; i++) {
        e.tickWith(_none, _none);
      }
      e.p1.x = 200;
      e.p2.x = 248;
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        e.p1.meter = Moves.meterMax;
        e.tickWith(_sp, _none);
        seen.add(e.p1.activeSpecial);
        _run(e, 55);
      }
      expect(seen, [
        'flare_rush',
        'blaze_arc',
        'backdraft',
        'scorch_fan',
        'quake_stomp',
      ]);
      expect(Specials.bossCycle.length, 16);
    });

    test('deterministic: directional specials and zones hash identically', () {
      String play() {
        final e = _fight('cancer', 'taurus', x1: 300, x2: 345);
        e.p1.meter = Moves.meterMax;
        e.p2.meter = Moves.meterMax;
        e.tickWith(_spD, _spD);
        _run(e, 60);
        return e.stateHash();
      }

      expect(play(), play());
    });
  });
}
