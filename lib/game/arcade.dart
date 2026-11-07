// Arcade run (spec 4.5): ladder, difficulty, continues and scoring. Pure Dart.
// Real: the 11 other signs in a seeded shuffle then the Ophiuchus boss, difficulty 0.15 -> 0.85 then 1.0,
// 3 continues, scoring (KO 1,000 + HP x10 + time left x20 + 500 perfect + 2,000 boss). A run lives in
// memory only and is never saved across app restarts.
import 'dart:math';

import '../npc/zodiac_offline.dart';
import 'fighter.dart';
import 'match_engine.dart';

class ArcadeScoring {
  ArcadeScoring._();
  static const ko = 1000;
  static const perHp = 10;
  static const perSecondLeft = 20;
  static const perfect = 500;
  static const bossBonus = 2000;

  /// Points for one round the player won. Lost or drawn rounds score nothing.
  static int round(RoundResult r, {required int playerSide}) {
    if (r.winner != playerSide) return 0;
    var p = r.winnerHp * perHp + r.secondsLeft * perSecondLeft;
    if (r.ko) p += ko;
    if (r.perfect) p += perfect;
    return p;
  }
}

enum RunStatus { fighting, lostAwaitingContinue, won, over }

class ArcadeRun {
  final int seed;
  final FighterDef player;

  /// 12 entries: 11 signs (not the player's) in seeded order, then the boss.
  final List<String> ladder;
  static const int startContinues = 3;
  static const double firstDifficulty = 0.15;
  static const double lastDifficulty = 0.85;
  static const double bossDifficulty = 1.0;

  int index = 0;
  int continuesLeft = startContinues;
  int score = 0;

  /// Points from rounds of the fight in progress (dropped on a loss; the HUD shows score + this).
  int fightPoints = 0;
  RunStatus status = RunStatus.fighting;

  ArcadeRun({required this.seed, required this.player})
    : ladder = buildLadder(seed, player.sign);

  static List<String> buildLadder(int seed, String playerSign) {
    final others = [
      for (final s in zodiacSigns)
        if (s != playerSign) s,
    ];
    // 11 others when the player is a zodiac sign; a player without a sign gets 11 of the 12 by seed.
    if (others.length == 12) others.removeAt(Random(seed ^ 0x5eed).nextInt(12));
    others.shuffle(Random(seed));
    return [...others, 'ophiuchus'];
  }

  int get length => ladder.length;
  bool get atBoss => index == ladder.length - 1;
  String get currentSign => ladder[index];

  /// Ladder position reached, 1-based (for high scores and feedback).
  int get reached => index + 1;

  static double difficultyAt(int i, int length) {
    if (i >= length - 1) return bossDifficulty;
    final steps = length - 2;
    if (steps <= 0) return firstDifficulty;
    return firstDifficulty + (lastDifficulty - firstDifficulty) * i / steps;
  }

  double get difficulty => difficultyAt(index, ladder.length);

  /// Per-fight seed: runSeed + index (also the OmniMind seed for this opponent).
  int get fightSeed => seed + index;

  /// The offline opponent for the current rung (OmniMind may replace it with a seeded one).
  FighterDef offlineOpponent() =>
      atBoss ? bossFighter() : offlineFighter(currentSign)!;

  int get liveScore => score + fightPoints;

  /// Feed each round result as it happens (from FIGHTER_ROUND_END).
  void onRound(RoundResult r, {int playerSide = 0}) {
    fightPoints += ArcadeScoring.round(r, playerSide: playerSide);
  }

  /// Call when the fight ends. Returns the new status.
  RunStatus onFightEnd({required bool playerWon}) {
    if (playerWon) {
      score += fightPoints;
      if (atBoss) score += ArcadeScoring.bossBonus;
      fightPoints = 0;
      if (atBoss) {
        status = RunStatus.won;
      } else {
        index++;
        status = RunStatus.fighting;
      }
    } else {
      // The lost fight's round bonuses are dropped; the score from earlier fights stays.
      fightPoints = 0;
      status = continuesLeft > 0
          ? RunStatus.lostAwaitingContinue
          : RunStatus.over;
    }
    return status;
  }

  /// Use a continue: refight the same opponent. False when none are left.
  bool useContinue() {
    if (status != RunStatus.lostAwaitingContinue || continuesLeft <= 0) {
      return false;
  }
    continuesLeft--;
    fightPoints = 0;
    status = RunStatus.fighting;
    return true;
  }

  void endRun() {
    fightPoints = 0;
    if (status != RunStatus.won) status = RunStatus.over;
  }

  bool get finished => status == RunStatus.won || status == RunStatus.over;
}
