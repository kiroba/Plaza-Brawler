// Fight screen (spec 4.3, 4.10): a thin view over the pure-Dart MatchEngine, stepped at a fixed 60 Hz from a
// Ticker. Real: HUD (HP, meter, centred timer, round pips, arcade score), touch pad (d-pad + L/H/B/S, each
// >= 56 dp) through TouchInput, desktop keys through KeyboardInput, CPU through CpuBrain, signed
// FIGHTER_MATCH_START / FIGHTER_ROUND_END events and the match summary saved via MatchShare, kiosk pause,
// and the CPU-vs-CPU attract loop. Placeholder art (lib/art/fighter_painter.dart). Hit-stop and KO slow-mo
// (lib/game/hit_feel.dart) only decide WHEN the engine ticks, so the engine stays deterministic; the K.O.
// banner waits for the slow-mo. Sounds (hit / block / KO) play in player fights, not in the attract loop.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../art/fighter_painter.dart';
import '../audio/sfx.dart';
import '../game/arcade.dart';
import '../game/cpu_brain.dart';
import '../game/fighter.dart';
import '../game/hit_feel.dart';
import '../game/input.dart';
import '../game/match_engine.dart';
import '../net/omni_node.dart';
import '../npc/omnimind.dart';
import 'brawler_ui.dart';

/// Everything a fight needs.
class FightConfig {
  final FighterDef p1;
  final FighterDef p2;
  final int seed;

  /// 'arcade' | 'quick' | 'attract'
  final String mode;

  /// CPU difficulty for P2 (0..1).
  final double difficulty;

  /// The arcade run (for the live score in the HUD and round scoring), or null.
  final ArcadeRun? run;

  const FightConfig({
    required this.p1,
    required this.p2,
    required this.seed,
    this.mode = 'quick',
    this.difficulty = 0.5,
    this.run,
  });

  bool get attract => mode == 'attract';
}

/// What the fight screen pops with.
class FightOutcome {
  final bool playerWon;
  final Map<String, dynamic> summary;
  const FightOutcome({required this.playerWon, required this.summary});
}

class FighterScreen extends StatefulWidget {
  final FightConfig config;
  const FighterScreen({super.key, required this.config});

  @override
  State<FighterScreen> createState() => _FighterScreenState();
}

class _FighterScreenState extends State<FighterScreen>
    with SingleTickerProviderStateMixin {
  static const int _stepMicros = 1000000 ~/ MatchEngine.ticksPerSecond;

  final TouchInput _touch = TouchInput();
  final KeyboardInput _keys = KeyboardInput();
  final FocusNode _focus = FocusNode();
  late MatchEngine _engine;
  late FightConfig _cfg;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _acc = 0;
  bool _paused = false;
  bool _ended = false;
  final List<int> _flash = [0, 0];
  int _shakeFrames = 0;
  final HitFeel _feel = HitFeel();
  final Random _fxRng = Random(7);
  int _attractRound = 0;

  @override
  void initState() {
    super.initState();
    _cfg = widget.config;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _touch.onActivity = appState.kiosk.noteActivity;
    _engine = _newEngine(_cfg);
    if (!_cfg.attract) appState.onPauseFight = _pauseFromKiosk;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    if (appState.onPauseFight == _pauseFromKiosk) appState.onPauseFight = null;
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  MatchEngine _newEngine(FightConfig c) {
    final InputSource p1 = c.attract
        ? CpuInput(
            CpuBrain(def: c.p1, difficulty: 0.6, seed: c.seed ^ 0x51),
            side: 0,
          )
        : MergedInput([_touch, _keys]);
    // PvP hook: a RemoteInput goes here instead of the CPU in the multiplayer PR (spec 11).
    final InputSource p2 = CpuInput(
      CpuBrain(def: c.p2, difficulty: c.difficulty, seed: c.seed),
      side: 1,
    );
    return MatchEngine(
      p1: c.p1,
      p2: c.p2,
      input1: p1,
      input2: p2,
      seed: c.seed,
      mode: c.mode,
    );
  }

  void _pauseFromKiosk() {
    if (!_paused && !_ended && mounted) {
      setState(() {
        _paused = true;
        _touch.releaseAll();
      });
    }
  }

  void _resume() {
    appState.kiosk.noteActivity();
    setState(() {
      _paused = false;
      _acc = 0;
    });
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (_paused || !mounted) return;
    _acc += dt.inMicroseconds;
    var steps = 0;
    while (_acc >= _stepMicros && steps < 5) {
      if (_shakeFrames > 0) _shakeFrames--;
      // Hit-stop / KO slow-mo: some display steps don't run the engine (see HitFeel).
      if (_feel.shouldTick()) {
        _engine.tick();
        _afterStep();
      }
      _acc -= _stepMicros;
      steps++;
    }
    if (steps == 5) _acc = 0; // fell behind (debugger, slow phone): drop time instead of spiralling
    if (steps > 0) setState(() {});
  }

  void _afterStep() {
    for (var s = 0; s < 2; s++) {
      if (_flash[s] > 0) _flash[s]--;
    }
    for (final fx in _engine.fx) {
      if (fx.defender >= 0 && fx.defender < 2)
        _flash[fx.defender] = fx.blocked ? 3 : 6;
      if (fx.heavy || fx.special || fx.ko || fx.guardBreak)
        _shakeFrames = 7; // ~120 ms
    }
    _feel.onFx(_engine.fx);
    if (!_cfg.attract) _playSounds();
    final events = _engine.drainEvents();
    if (!_cfg.attract) {
      for (final e in events) {
        if (e.type == 'FIGHTER_ROUND_END') {
          if (_engine.results.isNotEmpty)
            _cfg.run?.onRound(_engine.results.last);
          omniNode.dispatchEvent(e.type, e.payload);
        } else if (e.type == 'FIGHTER_MATCH_END') {
          appState.matchShare.shareMatch(e.payload);
        } else {
          omniNode.dispatchEvent(e.type, e.payload);
        }
      }
    }
    if (_engine.isOver && !_ended) {
      _ended = true;
      Future.delayed(const Duration(milliseconds: 1600), _finish);
    }
  }

  /// At most one of each sound per frame (Flare Rush and traded hits can land twice in one frame).
  void _playSounds() {
    final fx = _engine.fx;
    if (fx.isEmpty) return;
    if (fx.any((f) => f.ko)) {
      sfx.ko();
      return;
    }
    if (fx.any((f) => !f.blocked || f.guardBreak)) sfx.hit();
    if (fx.any((f) => f.blocked && !f.guardBreak)) sfx.block();
  }

  void _finish() {
    if (!mounted) return;
    if (_cfg.attract) {
      // Attract loop: next CPU pair.
      _attractRound++;
      final pair = omniMindOpponents.attractPair(
        _cfg.seed + _attractRound * 13,
      );
      setState(() {
        _cfg = FightConfig(
          p1: pair[0],
          p2: pair[1],
          seed: _cfg.seed + _attractRound,
          mode: 'attract',
          difficulty: 0.6,
        );
        _engine = _newEngine(_cfg);
        _feel.reset();
        _ended = false;
      });
      return;
    }
    Navigator.of(context).pop(
      FightOutcome(
        playerWon: _engine.matchWinner == 0,
        summary: _engine.summary(),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final label = event.logicalKey.keyLabel.toLowerCase();
    bool mine = false;
    if (event is KeyDownEvent) {
      mine = _keys.keyDown(label);
    } else if (event is KeyUpEvent) {
      mine = _keys.keyUp(label);
    } else if (event is KeyRepeatEvent) {
      mine = KeyboardInput.keymap.containsKey(label);
    }
    if (mine) appState.kiosk.noteActivity();
    return mine ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final shake = _shakeFrames > 0
        ? Offset(
            (_fxRng.nextDouble() * 2 - 1) * 3,
            (_fxRng.nextDouble() * 2 - 1) * 3,
          )
        : Offset.zero;
    return PopScope(
      canPop: !appState.kioskOn || _cfg.attract,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxHeight < 420;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ArenaPainter(
                          engine: _engine,
                          flash: _flash,
                          shake: shake,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      top: 4,
                      child: _Hud(engine: _engine, run: _cfg.run),
                    ),
                    if (!_cfg.attract)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: _TouchPad(input: _touch, compact: compact),
                      ),
                    if (_engine.phase == MatchPhase.intro && !_cfg.attract)
                      _Banner(text: 'ROUND ${_engine.round}'),
                    if ((_engine.phase == MatchPhase.roundOver ||
                            _engine.phase == MatchPhase.matchOver) &&
                        !_feel.holdingKo)
                      _Banner(text: _roundText()),
                    if (_cfg.attract) const _AttractOverlay(),
                    if (_paused) _PauseOverlay(onResume: _resume),
                    if (!_cfg.attract && !appState.kioskOn)
                      Positioned(
                        top: 40,
                        right: 4,
                        child: IconButton(
                          tooltip: 'Pause',
                          icon: const Icon(
                            Icons.pause_circle,
                            color: Colors.white54,
                          ),
                          onPressed: _pauseFromKiosk,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _roundText() {
    if (_engine.phase == MatchPhase.matchOver || _engine.isOver) {
      final w = _engine.matchWinner;
      if (w == null) return 'DRAW';
      if (_cfg.attract)
        return '${_engine.fighter(w).def.name.toUpperCase()} WINS';
      return w == 0 ? 'YOU WIN!' : 'YOU LOSE';
    }
    final r = _engine.results.isEmpty ? null : _engine.results.last;
    if (r == null) return '';
    if (r.winner == null) return 'DRAW ROUND';
    final ko = r.ko ? 'K.O.' : 'TIME';
    return r.perfect ? '$ko  PERFECT!' : ko;
  }
}

class _Hud extends StatelessWidget {
  final MatchEngine engine;
  final ArcadeRun? run;
  const _Hud({required this.engine, this.run});

  @override
  Widget build(BuildContext context) {
    final snap = engine.snapshot;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SideBars(
                f: engine.p1,
                wins: engine.wins[0],
                mirror: false,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: BrawlerColors.cyan.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                '${snap.secondsLeft}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _SideBars(
                f: engine.p2,
                wins: engine.wins[1],
                mirror: true,
              ),
            ),
          ],
        ),
        if (run != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'SCORE ${run!.liveScore}   FIGHT ${run!.reached}/${run!.length}',
              style: const TextStyle(
                color: BrawlerColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _SideBars extends StatelessWidget {
  final FighterState f;
  final int wins;
  final bool mirror;
  const _SideBars({required this.f, required this.wins, required this.mirror});

  Widget _bar(double frac, Color color, double h) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: h,
      child: LinearProgressIndicator(
        value: frac.clamp(0.0, 1.0),
        backgroundColor: Colors.white12,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final hpFrac = f.hpFraction;
    final hpColor = hpFrac > 0.5
        ? Colors.greenAccent
        : (hpFrac > 0.25 ? Colors.amber : BrawlerColors.red);
    final pips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < MatchEngine.winsNeeded; i++)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < wins ? BrawlerColors.gold : Colors.transparent,
              border: Border.all(color: BrawlerColors.gold),
            ),
          ),
      ],
    );
    final name = Flexible(
      child: Text(
        f.def.name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: mirror
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: mirror
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: mirror
              ? [pips, const SizedBox(width: 4), name]
              : [name, const SizedBox(width: 4), pips],
        ),
        const SizedBox(height: 2),
        Transform.flip(flipX: mirror, child: _bar(hpFrac, hpColor, 10)),
        const SizedBox(height: 2),
        Transform.flip(
          flipX: mirror,
          child: _bar(
            f.meter / 100.0,
            f.meter >= 100 ? BrawlerColors.gold : BrawlerColors.cyan,
            5,
          ),
        ),
      ],
    );
  }
}

/// D-pad bottom left (left, jump, right), actions bottom right (L, H, B, S). Each pad is >= 56 dp.
class _TouchPad extends StatelessWidget {
  final TouchInput input;
  final bool compact;
  const _TouchPad({required this.input, required this.compact});

  @override
  Widget build(BuildContext context) {
    const s = 56.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Pad(label: '◀', flag: FighterIntent.left, input: input, size: s),
        const SizedBox(width: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pad(label: '▲', flag: FighterIntent.up, input: input, size: s),
            if (!compact) const SizedBox(height: s / 2),
          ],
        ),
        const SizedBox(width: 6),
        _Pad(label: '▶', flag: FighterIntent.right, input: input, size: s),
        const Spacer(),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Pad(
                  label: 'B',
                  flag: FighterIntent.block,
                  input: input,
                  size: s,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                _Pad(
                  label: 'S',
                  flag: FighterIntent.special,
                  input: input,
                  size: s,
                  color: BrawlerColors.gold,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Pad(
                  label: 'L',
                  flag: FighterIntent.light,
                  input: input,
                  size: s,
                  color: BrawlerColors.cyan,
                ),
                const SizedBox(width: 6),
                _Pad(
                  label: 'H',
                  flag: FighterIntent.heavy,
                  input: input,
                  size: s,
                  color: BrawlerColors.red,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Pad extends StatefulWidget {
  final String label;
  final int flag;
  final TouchInput input;
  final double size;
  final Color color;
  const _Pad({
    required this.label,
    required this.flag,
    required this.input,
    required this.size,
    this.color = Colors.white,
  });

  @override
  State<_Pad> createState() => _PadState();
}

class _PadState extends State<_Pad> {
  bool _down = false;

  void _set(bool down) {
    if (down == _down) return;
    setState(() => _down = down);
    if (down) {
      widget.input.press(widget.flag);
    } else {
      widget.input.release(widget.flag);
    }
  }

  @override
  void dispose() {
    if (_down) widget.input.release(widget.flag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _down ? 0.55 : 0.22),
          border: Border.all(
            color: widget.color.withValues(alpha: 0.8),
            width: 2,
          ),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Center(
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: const TextStyle(
              color: BrawlerColors.gold,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
        ),
      ),
    );
  }
}

/// "TAP TO PLAY" over the CPU-vs-CPU loop. Any tap leaves it.
class _AttractOverlay extends StatefulWidget {
  const _AttractOverlay();

  @override
  State<_AttractOverlay> createState() => _AttractOverlayState();
}

class _AttractOverlayState extends State<_AttractOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Align(
          alignment: const Alignment(0, 0.6),
          child: FadeTransition(
            opacity: _blink,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PLAZA BRAWLER',
                  style: TextStyle(
                    color: BrawlerColors.cyan,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'TAP TO PLAY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  const _PauseOverlay({required this.onResume});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onResume,
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PAUSED',
                  style: TextStyle(
                    color: BrawlerColors.gold,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Tap to keep playing',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
