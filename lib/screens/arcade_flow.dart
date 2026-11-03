// Navigation for Arcade and Quick Fight (spec 4.5, 4.10). Real: character select -> how to play (first time)
// -> [VS splash -> fight] x 12 with continues -> run end -> initials (top 10 only) -> high scores ->
// feedback -> title; Quick Fight with feedback every third fight. Every step awaits a named route, and a
// kiosk "return to title" (new session id) or a back press ends the flow cleanly. A FlowBackdrop route sits
// under the whole flow, so the title never flashes between steps (VS -> fight -> result -> next VS).
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/arcade.dart';
import '../game/fighter.dart';
import '../game/records.dart';
import '../net/omni_node.dart';
import 'brawler_ui.dart';
import 'character_select_screen.dart';
import 'feedback_screen.dart';
import 'fighter_screen.dart';
import 'game_over_screen.dart';
import 'high_scores_screen.dart';
import 'how_to_play_screen.dart';
import 'initials_screen.dart';
import 'run_end_screen.dart';
import 'versus_splash.dart';

class ArcadeFlow {
  ArcadeFlow._();

  static bool _busy = false;
  static final Random _rng = Random();

  static int get _session => appState.kiosk.session.id;

  static Future<void> startArcade() => _guard(_arcade);
  static Future<void> startQuickFight() => _guard(_quick);

  static Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    final backdrop = brawlerRoute<void>(
      Routes.flow,
      (_) => const FlowBackdrop(),
    );
    final nav = navigatorKey.currentState;
    if (nav != null) unawaited(nav.push(backdrop));
    try {
      await f();
    } finally {
      _busy = false;
      _dropBackdrop(backdrop);
    }
  }

  /// Takes the backdrop away when the flow ends some other way than [_toTitle] (back press, kiosk reset
  /// already popped everything, a null result).
  static void _dropBackdrop(Route<void> backdrop) {
    final nav = navigatorKey.currentState;
    if (nav == null || !backdrop.isActive) return;
    if (backdrop.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(backdrop);
    }
  }

  static void _toTitle() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    if (appState.kioskOn) appState.kiosk.resetSession();
  }

  /// The player's fighter: the LPE profile's own sign if it ever has one, else the sign picked here.
  static Future<FighterDef?> _pickPlayer(int session) async {
    if (!appState.kioskOn) {
      final lpeSign = omniNode.lpeSign;
      if (lpeSign != null) return omniNode.playerFighter(lpeSign);
    }
    final sign = await pushNamedPage<String>(
      Routes.select,
      CharacterSelectScreen(
        title: 'CHOOSE YOUR FIGHTER',
        preselected: appState.kioskOn ? null : appState.chosenSign,
      ),
    );
    if (sign == null || session != _session) return null;
    await appState.setChosenSign(sign);
    return omniNode.playerFighter(sign);
  }

  static Future<bool> _howToPlayIfNeeded(int session) async {
    if (!appState.needsHowToPlay) return true;
    final ok = await pushNamedPage<bool>(
      Routes.howToPlay,
      const HowToPlayScreen(),
    );
    return ok == true && session == _session;
  }

  static Future<void> _arcade() async {
    final session = _session;
    final player = await _pickPlayer(session);
    if (player == null) return;
    if (!await _howToPlayIfNeeded(session)) return;

    final seed = appState.kioskOn
        ? appState.kiosk.session.runSeed
        : _rng.nextInt(1 << 31);
    final run = ArcadeRun(seed: seed, player: player);
    while (!run.finished) {
      final opp = await omniNode.opponent(run.currentSign, run.fightSeed);
      if (session != _session) return;
      final go = await pushNamedPage<bool>(
        Routes.versus,
        VersusSplash(
          p1: player,
          p2: opp,
          subtitle: run.atBoss
              ? 'FINAL FIGHT'
              : 'FIGHT ${run.reached} OF ${run.length}',
        ),
      );
      if (go != true || session != _session) return;
      final out = await pushNamedPage<FightOutcome>(
        Routes.fight,
        FighterScreen(
          config: FightConfig(
            p1: player,
            p2: opp,
            seed: run.fightSeed,
            mode: 'arcade',
            difficulty: run.difficulty,
            run: run,
          ),
        ),
      );
      if (out == null || session != _session) return;
      final status = run.onFightEnd(playerWon: out.playerWon);
      if (status == RunStatus.lostAwaitingContinue) {
        final cont = await _askContinue(run);
        if (cont == null || session != _session) return;
        if (cont) {
          run.useContinue();
        } else {
          run.endRun();
        }
      }
    }
    await _runEnd(run, session);
  }

  static Future<bool?> _askContinue(ArcadeRun run) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return null;
    return showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: Routes.dialog),
      builder: (c) => AlertDialog(
        backgroundColor: BrawlerColors.panel,
        title: const Text(
          'CONTINUE?',
          style: TextStyle(
            color: BrawlerColors.gold,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Continues left: ${run.continuesLeft}\nScore so far: ${run.score}\n'
          'Continuing refights this opponent.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('END RUN'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }

  static Future<void> _runEnd(ArcadeRun run, int session) async {
    final seen = await pushNamedPage<bool>(
      Routes.runEnd,
      RunEndScreen(run: run),
    );
    if (seen == null || session != _session) return;

    if (await appState.highScores.qualifies(run.score)) {
      if (session != _session) return;
      final initials = await pushNamedPage<String>(
        Routes.initials,
        InitialsScreen(score: run.score),
      );
      if (session != _session) return;
      if (initials != null) {
        final entry = HighScoreEntry(
          initials: initials,
          score: run.score,
          sign: run.player.sign,
          reached: run.reached,
          ts: DateTime.now().millisecondsSinceEpoch,
        );
        final rank = await appState.highScores.add(entry);
        omniNode.dispatchEvent('ARCADE_SCORE', {
          'initials': HighScoreRules.cleanInitials(initials),
          'score': run.score,
          'sign': run.player.sign,
          'reached': run.reached,
          'rank': rank,
        });
        if (session != _session) return;
        await pushNamedPage<void>(
          Routes.highScores,
          HighScoresScreen(highlightTs: entry.ts),
        );
        if (session != _session) return;
      }
    }

    await pushNamedPage<bool>(
      Routes.feedback,
      FeedbackScreen(
        mode: 'arcade',
        sign: run.player.sign,
        reached: run.reached,
        score: run.score,
      ),
    );
    if (session != _session) return;
    _toTitle();
  }

  static Future<void> _quick() async {
    final session = _session;
    final player = await _pickPlayer(session);
    if (player == null) return;
    final plaza = await omniNode.plazaChallenger();
    if (session != _session) return;
    final pick = await pushNamedPage<String>(
      Routes.select,
      CharacterSelectScreen(
        title: 'CHOOSE OPPONENT',
        opponentMode: true,
        plaza: plaza,
      ),
    );
    if (pick == null || session != _session) return;
    if (!await _howToPlayIfNeeded(session)) return;

    var seed = _rng.nextInt(1 << 31);
    final opp = pick == 'plaza' && plaza != null
        ? plaza
        : await omniNode.opponent(pick, seed);
    if (session != _session) return;
    final go = await pushNamedPage<bool>(
      Routes.versus,
      VersusSplash(p1: player, p2: opp, subtitle: 'QUICK FIGHT'),
    );
    if (go != true || session != _session) return;

    while (true) {
      final out = await pushNamedPage<FightOutcome>(
        Routes.fight,
        FighterScreen(
          config: FightConfig(
            p1: player,
            p2: opp,
            seed: seed,
            mode: 'quick',
            difficulty: 0.5,
          ),
        ),
      );
      if (out == null || session != _session) return;
      appState.quickFights++;
      final next = await pushNamedPage<String>(
        Routes.gameOver,
        GameOverScreen(won: out.playerWon, player: player, opponent: opp),
      );
      if (session != _session) return;
      if (appState.quickFights % 3 == 0) {
        await pushNamedPage<bool>(
          Routes.feedback,
          FeedbackScreen(
            mode: 'quick',
            sign: player.sign,
            reached: 0,
            score: 0,
          ),
        );
        if (session != _session) return;
      }
      if (next != 'retry') break;
      seed = _rng.nextInt(1 << 31);
    }
    _toTitle();
  }
}
