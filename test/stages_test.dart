import 'package:flutter_test/flutter_test.dart';
import 'package:plaza_brawler/game/stages.dart';

void main() {
  group('Stages.forMatch', () {
    test('a lone fire fighter owns the fire arena', () {
      expect(
        Stages.forMatch(p1Element: 'fire', p2Element: 'earth', seed: 0),
        Stages.fireArena,
      );
      expect(
        Stages.forMatch(p1Element: 'earth', p2Element: 'fire', seed: 1),
        Stages.fireArena,
      );
    });

    test('a lone water fighter owns the water arena', () {
      expect(
        Stages.forMatch(p1Element: 'water', p2Element: 'air', seed: 2),
        Stages.waterArena,
      );
      expect(
        Stages.forMatch(p1Element: 'air', p2Element: 'water', seed: 0),
        Stages.waterArena,
      );
    });

    test('fire against water meets at the plaza', () {
      final s = Stages.forMatch(p1Element: 'fire', p2Element: 'water', seed: 0);
      expect(Stages.plazas, contains(s));
    });

    test('element order does not matter (PvP sides agree)', () {
      for (final seed in [0, 1, 2, 7, 42]) {
        expect(
          Stages.forMatch(p1Element: 'earth', p2Element: 'water', seed: seed),
          Stages.forMatch(p1Element: 'water', p2Element: 'earth', seed: seed),
        );
        expect(
          Stages.forMatch(p1Element: 'fire', p2Element: 'water', seed: seed),
          Stages.forMatch(p1Element: 'water', p2Element: 'fire', seed: seed),
        );
      }
    });

    test('the plaza rotates through all three by seed', () {
      final seen = <String>{
        for (var seed = 0; seed < 3; seed++)
          Stages.forMatch(p1Element: 'earth', p2Element: 'air', seed: seed),
      };
      expect(seen, Stages.plazas.toSet());
    });
  });

  group('Stages.animatedFor', () {
    test('every still maps to its animated webp twin', () {
      expect(Stages.animatedFor(Stages.plazaDawn), Stages.plazaDawnAnimated);
      expect(Stages.animatedFor(Stages.plazaDusk), Stages.plazaDuskAnimated);
      expect(Stages.animatedFor(Stages.plazaNight), Stages.plazaNightAnimated);
      expect(Stages.animatedFor(Stages.fireArena), Stages.fireArenaAnimated);
      expect(Stages.animatedFor(Stages.waterArena), Stages.waterArenaAnimated);
    });

    test('unknown paths pass through unchanged', () {
      expect(
        Stages.animatedFor('assets/stages/other.jpg'),
        'assets/stages/other.jpg',
      );
    });

    test('the animated set covers every still', () {
      expect(Stages.animatedAll.length, Stages.all.length);
      for (final still in Stages.all) {
        expect(Stages.animatedAll, contains(Stages.animatedFor(still)));
      }
    });
  });
}
