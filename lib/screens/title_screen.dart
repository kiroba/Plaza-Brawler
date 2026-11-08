// Title screen (spec 4.10, 5.4), replaces menu_screen.dart. Real: PLAZA BRAWLER logo, the menu (ARCADE,
// QUICK FIGHT, HIGH SCORES, HOW TO PLAY, SETTINGS hidden in kiosk mode), the live Node/LPE/OmniMind status
// chips (filled = connected, hollow = offline; tap opens Settings outside kiosk mode), the kiosk attract loop
// after 20 s idle, and the hidden exit: hold the logo for 3 s, then the PIN (5 wrong PINs lock it for 30 s).
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/kiosk.dart';
import '../net/omni_node.dart';
import '../npc/omnimind.dart';
import 'arcade_flow.dart';
import 'brawler_ui.dart';
import 'fighter_screen.dart';
import 'high_scores_screen.dart';
import 'how_to_play_screen.dart';
import 'settings_screen.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  Timer? _holdTimer;
  bool _attractOpen = false;
  int _attractCount = 0;

  @override
  void initState() {
    super.initState();
    appState.onStartAttract = _startAttract;
    appState.addListener(_changed);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    appState.removeListener(_changed);
    if (appState.onStartAttract == _startAttract) {
      appState.onStartAttract = null;
  }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _startAttract() async {
    if (_attractOpen || !mounted) return;
    _attractOpen = true;
    _attractCount++;
    final seed = DateTime.now().millisecondsSinceEpoch ^ _attractCount;
    final pair = omniMindOpponents.attractPair(seed);
    await pushNamedPage<FightOutcome>(
      Routes.attract,
      FighterScreen(
        config: FightConfig(
          p1: pair[0],
          p2: pair[1],
          seed: seed & 0x7fffffff,
          mode: 'attract',
          difficulty: 0.6,
        ),
      ),
    );
    _attractOpen = false;
    // A tap ended the loop: a new player is here.
    appState.kiosk.resetSession();
  }

  // ---- hidden exit: 3 s hold on the logo, then the PIN
  void _logoDown() {
    if (!appState.kioskOn) return;
    appState.kiosk.logoDown();
    _holdTimer?.cancel();
    // Poll while the finger is down instead of one shot at exactly 3 s: a
    // one-shot timer can fire a millisecond early, fail the >= 3 s check in
    // logoHeld(), and never ask again while the operator keeps holding.
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (appState.kiosk.logoHeld()) {
        _holdTimer?.cancel();
        _askPin();
      }
    });
  }

  void _logoUp() {
    _holdTimer?.cancel();
    appState.kiosk.logoUp();
  }

  Future<void> _askPin() async {
    if (!mounted) return;
    if (appState.kiosk.pinLockedMs > 0) {
      appState.kiosk.cancelExitPrompt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Too many wrong PINs. Try again in ${(appState.kiosk.pinLockedMs / 1000).ceil()} s.',
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: Routes.dialog),
      builder: (_) => const _ExitPinDialog(),
    );
    if (appState.kiosk.exitPromptOpen) appState.kiosk.cancelExitPrompt();
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = appState.kioskOn;
    return PopScope(
      canPop: !kiosk,
      child: BrawlerPage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Listener(
              onPointerDown: (_) => _logoDown(),
              onPointerUp: (_) => _logoUp(),
              onPointerCancel: (_) => _logoUp(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: BrawlerColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BrawlerColors.cyan, width: 2),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    children: [
                      Text(
                        'PLAZA BRAWLER',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: BrawlerColors.cyan,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Beat the 12 signs. Then face the 13th.',
                        style: TextStyle(
                          fontSize: 12,
                          color: BrawlerColors.gold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            BigButton(
              'ARCADE',
              icon: Icons.emoji_events,
              onPressed: () => ArcadeFlow.startArcade(),
            ),
            BigButton(
              'QUICK FIGHT',
              icon: Icons.sports_mma,
              color: BrawlerColors.gold,
              onPressed: () => ArcadeFlow.startQuickFight(),
            ),
            BigButton(
              'HIGH SCORES',
              icon: Icons.leaderboard,
              color: BrawlerColors.panel,
              textColor: Colors.white,
              onPressed: () => pushNamedPage<void>(
                Routes.highScores,
                const HighScoresScreen(),
              ),
            ),
            BigButton(
              'HOW TO PLAY',
              icon: Icons.help_outline,
              color: BrawlerColors.panel,
              textColor: Colors.white,
              onPressed: () => pushNamedPage<bool>(
                Routes.howToPlay,
                const HowToPlayScreen(),
              ),
            ),
            if (!kiosk)
              BigButton(
                'SETTINGS',
                icon: Icons.settings,
                color: BrawlerColors.panel,
                textColor: Colors.white,
                onPressed: _openSettings,
              ),
            const SizedBox(height: 16),
            _StatusChips(onTap: kiosk ? null : _openSettings),
            if (kiosk)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Demo-day mode · hold the logo to exit',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await pushNamedPage<void>(Routes.settings, const SettingsScreen());
    if (mounted) setState(() {});
  }
}

/// Node ●/○, LPE ●/○, OmniMind ●/○ (spec 5.4). Only real states.
class _StatusChips extends StatelessWidget {
  final VoidCallback? onTap;
  const _StatusChips({this.onTap});

  Widget _chip(String label, bool on) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      '$label ${on ? '●' : '○'}',
      style: TextStyle(
        color: on ? Colors.greenAccent : Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chip('Node', omniNode.isConnected),
              _chip('LPE', omniNode.lpeConnected),
              _chip('OmniMind', omniNode.omniMindConnected),
            ],
          ),
        ),
      ),
    );
  }
}

/// PIN prompt for the hidden exit. "Reset demo data" also needs the PIN.
class _ExitPinDialog extends StatefulWidget {
  const _ExitPinDialog();

  @override
  State<_ExitPinDialog> createState() => _ExitPinDialogState();
}

class _ExitPinDialogState extends State<_ExitPinDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _exit() async {
    final ok = await appState.submitExitPin(_pin.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    final locked = appState.kiosk.pinLockedMs;
    if (locked > 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = 'Wrong PIN';
      _pin.clear();
    });
  }

  Future<void> _reset() async {
    if (!appState.kiosk.checkPin(_pin.text.trim())) {
      setState(() => _error = 'Enter the PIN first');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: Routes.dialog),
      builder: (c) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This deletes every high score and feedback response on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await appState.resetDemoData();
    if (!mounted) return;
    setState(() => _error = 'Demo data cleared');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Demo-day mode'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: (_) => appState.kiosk.noteActivity(),
              decoration: InputDecoration(
                labelText: '4-digit PIN',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            appState.kiosk.cancelExitPrompt();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _reset, child: const Text('Reset data')),
        TextButton(onPressed: _exit, child: const Text('Exit demo mode')),
      ],
    );
  }
}
