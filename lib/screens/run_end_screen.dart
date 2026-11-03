// End of an arcade run (spec 4.5). Real: final score, ladder position, continues used, and whether the boss
// fell. Pops true on NEXT; in kiosk mode it goes back to the title after 10 s idle (lib/game/kiosk.dart).
import 'package:flutter/material.dart';

import '../game/arcade.dart';
import 'brawler_ui.dart';

class RunEndScreen extends StatelessWidget {
  final ArcadeRun run;
  const RunEndScreen({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final won = run.status == RunStatus.won;
    return BrawlerPage(
      title: won ? 'YOU BEAT THE 13TH SIGN!' : 'RUN OVER',
      showBack: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            won ? 'CHAMPION' : 'GOOD FIGHT',
            style: TextStyle(
              color: won ? BrawlerColors.gold : BrawlerColors.cyan,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _stat('Score', '${run.score}'),
          _stat('Reached', 'Fight ${run.reached} of ${run.length}'),
          _stat(
            'Continues used',
            '${ArcadeRun.startContinues - run.continuesLeft}',
          ),
          _stat('Fighter', '${run.player.name} (${run.player.signTitle})'),
          const SizedBox(height: 24),
          BigButton('NEXT', onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
  }

  Widget _stat(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}
