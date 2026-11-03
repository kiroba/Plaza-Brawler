// VS splash between fights (spec 4.5, 5.2). Real: both names and signs, the opponent's one-line taunt from
// its temperament, and a source chip ("OmniMind" only when the node generated this opponent, else
// "Offline"/"LPE"/"Plaza"). Shows for 2 s, tap to skip. Pops true to go on to the fight.
import 'dart:async';

import 'package:flutter/material.dart';

import '../art/fighter_painter.dart';
import '../game/fighter.dart';
import '../npc/omnimind.dart';
import '../npc/zodiac_offline.dart';
import 'brawler_ui.dart';

class VersusSplash extends StatefulWidget {
  final FighterDef p1;
  final FighterDef p2;
  final String subtitle;

  const VersusSplash({
    super.key,
    required this.p1,
    required this.p2,
    this.subtitle = '',
  });

  @override
  State<VersusSplash> createState() => _VersusSplashState();
}

class _VersusSplashState extends State<VersusSplash> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _go);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(true);
  }

  Widget _side(FighterDef f, bool right) {
    final chip = OmniMindOpponents.chip(f);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FighterPortrait(def: f, size: 96, facingRight: !right),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            f.name,
            style: TextStyle(
              color: Color(f.primary),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          f.signTitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SourceChip(
          chip,
          live: chip == 'OmniMind' || chip == 'LPE' || chip == 'Plaza',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrawlerColors.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.subtitle.isNotEmpty)
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: BrawlerColors.gold,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _side(widget.p1, false)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: BrawlerColors.red,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(child: _side(widget.p2, true)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '"${tauntFor(widget.p2)}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tap to skip',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
