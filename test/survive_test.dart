// Survive endless mode (flutter test): run progression, opponent cycling,
// difficulty tiering, round scoring, and best-run persistence.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plaza_brawler/app_state.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/game/survive.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:plaza_brawler/screens/survive_end_screen.dart';

const _kSurviveBest = 'plaza_brawler_survive_best_v1';

/// In-memory flutter_secure_storage: the MethodChannel the plugin uses.
/// (Same shape as test/secret_unlock_test.dart.)
Future<Object?> _storageHandler(
  Map<String, String> store,
  MethodCall call,
) async {
  final args = call.arguments is Map ? call.arguments as Map : const {};
  final key = args['key'] as String?;
  switch (call.method) {
    case 'read':
      return store[key];
    case 'containsKey':
      return store.containsKey(key);
    case 'write':
      if (key != null) store[key] = (args['value'] as String?) ?? '';
      return null;
    case 'delete':
      store.remove(key);
      return null;
    case 'deleteAll':
      store.clear();
      return null;
    case 'readAll':
      return Map<String, String>.from(store);
    default:
      return null;
  }
}

SurviveRun _run() =>
    SurviveRun(seed: 7, player: offlineFighter('aries')!);

void _win(SurviveRun run, [int times = 1]) {
  for (var i = 0; i < times; i++) {
    run.onFightEnd(playerWon: true);
  }
}

void main() {
  group('SurviveRun progression', () {
    test('starts at stage 1 against Aries', () {
      final run = _run();
      expect(run.stage, 0);
      expect(run.stageNumber, 1);
      expect(run.opponentsBeaten, 0);
      expect(run.currentSign, 'aries');
      expect(run.atBoss, isFalse);
      expect(run.finished, isFalse);
      expect(run.cycle, 0);
    });

    test('a win advances one stage; a loss ends the run', () {
      final run = _run();
      _win(run, 3);
      expect(run.stage, 3);
      expect(run.opponentsBeaten, 3);
      expect(run.currentSign, 'cancer');
      expect(run.finished, isFalse);

      run.onFightEnd(playerWon: false);
      expect(run.finished, isTrue);
      expect(run.opponentsBeaten, 3);
      expect(run.stage, 3);
    });

    test('opponents cycle the 12 signs in daemon order', () {
      final run = _run();
      final seen = <String>[];
      for (var i = 0; i < 12; i++) {
        seen.add(run.currentSign);
        _win(run);
      }
      expect(seen, zodiacSigns);
    });

    test('every 13th stage is Ophiuchus, then the cycle restarts', () {
      final run = _run();
      _win(run, 12);
      expect(run.stage, 12);
      expect(run.atBoss, isTrue);
      expect(run.currentSign, 'ophiuchus');
      expect(run.offlineOpponent().isBoss, isTrue);

      _win(run);
      expect(run.stage, 13);
      expect(run.cycle, 1);
      expect(run.atBoss, isFalse);
      expect(run.currentSign, 'aries');
    });

    test('difficulty ramps 0.15 -> 0.85, boss 1.0', () {
      final run = _run();
      expect(run.difficulty, closeTo(0.15, 0.0001));
      _win(run, 11);
      expect(run.difficulty, closeTo(0.85, 0.0001));
      _win(run);
      expect(run.difficulty, 1.0);
    });

    test('each completed cycle raises the ramp 0.10, clamped at 1.0', () {
      final run = _run();
      _win(run, 13);
      expect(run.difficulty, closeTo(0.25, 0.0001));
      _win(run, 11);
      expect(run.difficulty, closeTo(0.95, 0.0001));
      _win(run, 13 * 8);
      expect(run.difficulty, 1.0);
    });

    test('fight seed is run seed + stage', () {
      final run = _run();
      expect(run.fightSeed, 7);
      _win(run, 5);
      expect(run.fightSeed, 12);
    });
  });

  group('SurviveRun scoring', () {
    test('round points bank on a win and drop on a loss', () {
      final run = _run();
      const round = RoundResult(
        round: 1,
        winner: 0,
        ko: true,
        winnerHp: 100,
        winnerMaxHp: 100,
        framesLeft: 1800,
      );
      run.onRound(round);
      expect(run.liveScore, 3100); // 1000 KO + 100 HP x10 + 30 s x20 + 500 perfect
      run.onFightEnd(playerWon: true);
      expect(run.score, 3100);
      expect(run.liveScore, 3100);

      run.onRound(round);
      expect(run.liveScore, 6200);
      run.onFightEnd(playerWon: false);
      expect(run.score, 3100);
      expect(run.liveScore, 3100);
    });

    test('a boss win adds the boss bonus', () {
      final run = _run();
      _win(run, 12);
      const round = RoundResult(
        round: 1,
        winner: 0,
        ko: true,
        winnerHp: 100,
        winnerMaxHp: 100,
        framesLeft: 1800,
      );
      run.onRound(round);
      run.onFightEnd(playerWon: true);
      expect(run.score, 3100 + 2000);
    });
  });

  group('best-run persistence', () {
    late Map<String, String> store;

    setUp(() {
      store = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'plugins.it_nomads.com/flutter_secure_storage',
            ),
            (call) => _storageHandler(store, call),
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'plugins.it_nomads.com/flutter_secure_storage',
            ),
            null,
          );
    });

    test('a best run survives a fresh AppState load; lower runs do not overwrite', () async {
      final first = AppState();
      await first.load();
      expect(first.surviveBest, 0);

      expect(await first.recordSurviveBest(5), isTrue);
      expect(first.surviveBest, 5);
      expect(store[_kSurviveBest], '5');

      expect(await first.recordSurviveBest(3), isFalse);
      expect(first.surviveBest, 5);
      expect(store[_kSurviveBest], '5');

      final second = AppState();
      await second.load();
      expect(second.surviveBest, 5);
    });
  });

  group('run-over screen', () {
    testWidgets('shows beaten and best, with Run again and Menu', (
      tester,
    ) async {
      final run = _run();
      _win(run, 2);
      run.onFightEnd(playerWon: false);
      String? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => SurviveEndScreen(
                      run: run,
                      best: 5,
                      isNewBest: true,
                    ),
                  ),
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('NEW BEST!'), findsOneWidget);
      expect(find.text('Opponents beaten'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Best run'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.text('RUN AGAIN'));
      await tester.pumpAndSettle();
      expect(popped, 'again');
    });
  });
}
