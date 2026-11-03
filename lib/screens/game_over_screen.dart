// Quick Fight result (spec 4.10). Real: win/lose with both fighters; pops 'retry' or 'menu'.
import 'package:flutter/material.dart';

import '../art/fighter_painter.dart';
import '../game/fighter.dart';
import 'brawler_ui.dart';

class GameOverScreen extends StatelessWidget {
  final bool won;
  final FighterDef player;
  final FighterDef opponent;

  const GameOverScreen({
    super.key,
    required this.won,
    required this.player,
    required this.opponent,
  });

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      showBack: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              won ? 'VICTORY!' : 'DEFEATED',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: won ? Colors.greenAccent : BrawlerColors.red,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FighterPortrait(def: player, size: 90),
              const SizedBox(width: 16),
              FighterPortrait(def: opponent, size: 90, facingRight: false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            won
                ? 'You beat ${opponent.name}.'
                : '${opponent.name} wins this one.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 24),
          BigButton(
            'REMATCH',
            onPressed: () => Navigator.of(context).pop('retry'),
          ),
          BigButton(
            'MENU',
            color: BrawlerColors.panel,
            textColor: Colors.white,
            onPressed: () => Navigator.of(context).pop('menu'),
          ),
        ],
      ),
    );
  }
}
