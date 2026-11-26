// Survive run (Nov 25, 2026): endless ladder. Pure Dart.
// Real: the 12 signs in daemon order, then the Ophiuchus boss every 13th
// stage; each full cycle raises the CPU difficulty one step. One loss ends
// the run — no continues. A run lives in memory only; only the best run
// (opponents beaten) is persisted, in AppState.
import '../npc/zodiac_offline.dart';
import 'arcade.dart';
import 'fighter.dart';
import 'match_engine.dart';

class SurviveRun {
  final int seed;
  final FighterDef player;

  /// Stages per cycle: 12 signs + the boss.
  static const int cycleLength = 13;

  /// CPU difficulty bump per completed cycle (added to the arcade ramp).
  static const double difficultyPerCycle = 0.10;

  /// 0-based stage index: 0 is the first fight.
  int stage = 0;
  int score = 0;

  /// Points from rounds of the fight in progress (dropped on a loss; the HUD shows score + this).
  int fightPoints = 0;

  /// True once a stage is lost.
  bool finished = false;

  SurviveRun({required this.seed, required this.player});

  /// Full cycles completed (a cycle ends on a boss win).
  int get cycle => stage ~/ cycleLength;

  /// Position inside the current cycle, 0..12 (12 is the boss).
  int get stageInCycle => stage % cycleLength;

  bool get atBoss => stageInCycle == cycleLength - 1;

  /// The sign of the current stage's opponent, 'ophiuchus' on boss stages.
  String get currentSign => atBoss ? 'ophiuchus' : zodiacSigns[stageInCycle];

  /// Stage number shown in the HUD, 1-based.
  int get stageNumber => stage + 1;

  /// Matches won so far — the run's length, and what the best-run record keeps.
  int get opponentsBeaten => stage;

  /// CPU difficulty for this stage: the arcade ramp over a 13-stage cycle
  /// (0.15 -> 0.85, boss 1.0), raised one step per completed cycle and
  /// clamped at 1.0. Opponent stats are never touched: the boss keeps the
  /// only 9s in the game.
  double get difficulty {
    if (atBoss) return ArcadeRun.bossDifficulty;
    final ramp = ArcadeRun.difficultyAt(stageInCycle, cycleLength);
    return (ramp + difficultyPerCycle * cycle).clamp(0.0, 1.0).toDouble();
  }

  /// Per-fight seed: runSeed + stage (also the OmniMind seed for this opponent).
  int get fightSeed => seed + stage;

  /// The offline opponent for the current stage (OmniMind may replace it with a seeded one).
  FighterDef offlineOpponent() =>
      atBoss ? bossFighter() : offlineFighter(currentSign)!;

  int get liveScore => score + fightPoints;

  /// Feed each round result as it happens (from FIGHTER_ROUND_END).
  void onRound(RoundResult r, {int playerSide = 0}) {
    fightPoints += ArcadeScoring.round(r, playerSide: playerSide);
  }

  /// Call when the fight ends. A win banks the round points and advances;
  /// a loss ends the run.
  void onFightEnd({required bool playerWon}) {
    if (playerWon) {
      score += fightPoints;
      if (atBoss) score += ArcadeScoring.bossBonus;
      fightPoints = 0;
      stage++;
    } else {
      // The lost fight's round bonuses are dropped; the score from earlier fights stays.
      fightPoints = 0;
      finished = true;
    }
  }
}
