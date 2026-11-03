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
    ['L', 'Light punch (chain up to 3)', 'J'],
    ['H', 'Heavy kick (slower, knocks back)', 'K'],
    ['B', 'Block (hold). 3 blocked hits fast = guard break', 'L'],
    ['S', 'Special (needs a full meter)', 'I / Space'],
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
