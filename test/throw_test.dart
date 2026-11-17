// Slice S2 (Nov 16, 2026): throw behaviour — the ruled small rule set.
// Range 50, startup 5, damage 10, unblockable, loses to strikes during startup,
// 6-frame throw-tech, no comboing into a throw, no grabbing airborne fighters.
import 'package:plaza_brawler/game/fighter.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/game/moves.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

const _none = FighterIntent.none;
const _throw = FighterIntent(FighterIntent.throwBtn);
const _block = FighterIntent(FighterIntent.block);
const _blockThrow = FighterIntent(FighterIntent.block | FighterIntent.throwBtn);
const _lp = FighterIntent(FighterIntent.lp);

FighterDef _f(String sign) => offlineFighter(sign)!;

/// A match already past its round intro, with the fighters placed at [x1] and [x2].
MatchEngine _fight(String s1, String s2, {double x1 = 200, double x2 = 240}) {
  final e = MatchEngine(p1: _f(s1), p2: _f(s2));
  for (var i = 0; i < MatchEngine.introFrames; i++) {
    e.tickWith(_none, _none);
  }
  expect(e.phase, MatchPhase.fight);
  e.p1.x = x1;
  e.p2.x = x2;
  return e;
}

void _run(
  MatchEngine e,
  int n, [
  FighterIntent a = _none,
  FighterIntent b = _none,
]) {
  for (var i = 0; i < n; i++) {
    e.tickWith(a, b);
  }
}

int _dmg(FighterDef d, int base) => (base * d.stats.damageMultiplier).round();

void main() {
  group('throw (S2)', () {
    test('lands for full damage on a blocking defender — block does nothing', () {
      final e = _fight('aries', 'taurus');
      _run(e, 5, _none, _block); // let the block come up
      expect(e.p2.blocking, isTrue);
      final hp0 = e.p2.hp;
      e.tickWith(_throw, _block);
      _run(e, 10, _none, _block);
      // Full throw damage, not the 20% chip a blocked strike would deal.
      expect(e.p2.hp, hp0 - _dmg(e.p1.def, Moves.throwMove.damage));
      expect(e.p2.action, FighterAction.hitstun);
      expect(e.p1.hitsLanded, 1);
    });

    test('the thrown defender is stunned longer than a struck one', () {
      final e = _fight('aries', 'taurus');
      e.tickWith(_throw, _none);
      // Tick to just after the grab connects (startup 5).
      _run(e, 5);
      expect(e.p2.action, FighterAction.hitstun);
      expect(e.p2.stunFrames, greaterThan(Moves.lp.hitstun));
    });

    test('whiffs out of range and recovers to idle', () {
      final e = _fight('aries', 'taurus', x1: 200, x2: 300);
      final hp0 = e.p2.hp;
      e.tickWith(_throw, _none);
      _run(e, 30);
      expect(e.p2.hp, hp0);
      expect(e.p1.hitsLanded, 0);
      expect(e.p1.action, FighterAction.idle);
    });

    test('a strike landing during throw startup interrupts the throw', () {
      final e = _fight('aries', 'taurus');
      final hp2 = e.p2.hp;
      e.tickWith(_throw, _none); // P1 starts the throw
      e.tickWith(_none, _lp); // P2's LP (startup 3) beats the startup (5)
      _run(e, 12);
      expect(e.p1.hp, lessThan(e.p1.maxHp)); // the LP landed
      expect(e.p2.hp, hp2); // the throw never connected
      expect(e.p2.hitsLanded, 1);
    });

    test('throw-tech: defender pressing throw inside the window cancels it', () {
      final e = _fight('aries', 'taurus');
      _run(e, 5, _none, _block);
      final hp1 = e.p1.hp, hp2 = e.p2.hp;
      e.tickWith(_throw, _block); // P1 starts the throw
      _run(e, 2, _none, _block);
      e.tickWith(_none, _blockThrow); // P2 techs, 3 frames into the startup
      _run(e, 2, _none, _block); // the grab connects (and is teched) in this span
      _run(e, 1); // one neutral tick so both read idle
      expect(e.p1.hp, hp1);
      expect(e.p2.hp, hp2);
      expect(e.p1.hitsLanded, 0);
      expect(e.p1.action, FighterAction.idle);
      expect(e.p2.action, FighterAction.idle);
      // Small pushback separated them.
      expect(e.p2.x - e.p1.x, greaterThan(40));
    });

    test('a late throw press (outside the window) does not tech', () {
      final e = _fight('aries', 'taurus');
      _run(e, 5, _none, _block);
      e.tickWith(_none, _blockThrow); // P2 presses throw far too early
      _run(e, 10, _none, _block); // window expires long before any grab
      final hp0 = e.p2.hp;
      e.tickWith(_throw, _block);
      _run(e, 10, _none, _block);
      expect(e.p2.hp, hp0 - _dmg(e.p1.def, Moves.throwMove.damage));
    });

    test('cannot be combo\'d into: a stunned defender cannot be thrown', () {
      final e = _fight('aries', 'taurus');
      e.p2.action = FighterAction.hitstun;
      e.p2.stunFrames = 30;
      final hp0 = e.p2.hp;
      e.tickWith(_throw, _none);
      _run(e, 12);
      expect(e.p2.hp, hp0);
      expect(e.p1.hitsLanded, 0);
    });

    test('cannot grab an airborne defender', () {
      final e = _fight('aries', 'taurus');
      e.p2.y = 40;
      final hp0 = e.p2.hp;
      e.tickWith(_throw, _none);
      _run(e, 12);
      expect(e.p2.hp, hp0);
      expect(e.p1.hitsLanded, 0);
    });

    test('a throw can KO', () {
      final e = _fight('aries', 'taurus');
      e.p2.hp = 5;
      e.tickWith(_throw, _none);
      _run(e, 8);
      expect(e.p2.isKo, isTrue);
    });

    test('simultaneous throws clash into a tech', () {
      final e = _fight('aries', 'taurus');
      final hp1 = e.p1.hp, hp2 = e.p2.hp;
      e.tickWith(_throw, _throw);
      _run(e, 10);
      expect(e.p1.hp, hp1);
      expect(e.p2.hp, hp2);
      expect(e.p1.hitsLanded, 0);
      expect(e.p2.hitsLanded, 0);
    });

    test('deterministic: same inputs, same hash, throws included', () {
      String play() {
        final e = _fight('aries', 'taurus');
        _run(e, 5, _none, _block);
        e.tickWith(_throw, _block);
        _run(e, 40, _none, _block);
        e.tickWith(_throw, _blockThrow);
        _run(e, 40);
        return e.stateHash();
      }

      expect(play(), play());
    });
  });
}
