// How-to-play card (spec 4.9). Real: the control diagram for the touch pad and keyboard, meter and rounds,
// and a big GOT IT button that marks the card as seen (per install, or per player in kiosk mode).
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'brawler_ui.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const _rows = [
    ['◀  ▶', 'Move left and right', 'A / D'],
    ['▲', 'Jump (attack in the air to hit a blocker)', 'W'],
    ['▼', 'Crouch (hold). Low block = crouch + block', 'S'],
    ['HP', 'High punch (chains up to 2)', 'U'],
    ['LP', 'Low punch — fastest, chains up to 3. Block it LOW', 'J'],
    ['HK', 'High kick — slow, big knockback, anti-air', 'I'],
    ['LK', 'Low kick — the low poke. Block it LOW', 'K'],
    ['B', 'Block (hold). Lows must be blocked low. 3 blocked hits fast = guard break', 'L'],
    ['T', 'Throw — unblockable at point blank; press throw as it lands to tech out', 'H'],
    ['S', 'Special (needs a full meter)', 'Space'],
    ['LP LP HK', 'Combos: hits that land while they reel count up. LP·LP·HP is the One-Two (+3 dmg); LP·LP·HK is the Plaza Finisher — faster, harder', 'J J I'],
    ['S + ▶/◀/▼', 'Special + direction: a different elemental ability — forward, back, or down. Sixteen across the four elements', 'Space + dir'],
  ];

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      title: 'HOW TO PLAY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BrawlerColors.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BrawlerColors.cyan),
                    ),
                    child: Text(
                      r[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r[1],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    r[2],
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Fill the meter by landing hits.\nBest of 3 rounds. 60 seconds a round.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BrawlerColors.gold,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          BigButton(
            'GOT IT',
            onPressed: () async {
              await appState.markHowToPlaySeen();
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );
  }
}
