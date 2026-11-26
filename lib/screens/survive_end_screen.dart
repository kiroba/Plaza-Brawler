// End of a Survive run. Real: opponents beaten, best run (with a NEW BEST
// flag when this run set it), Run again / Menu. Pops 'again' or 'menu'.
import 'package:flutter/material.dart';

import '../game/survive.dart';
import 'brawler_ui.dart';

class SurviveEndScreen extends StatelessWidget {
  final SurviveRun run;

  /// Best run on this phone, opponents beaten (after this run was recorded).
  final int best;

  /// True when this run set the best.
  final bool isNewBest;

  const SurviveEndScreen({
    super.key,
    required this.run,
    required this.best,
    this.isNewBest = false,
  });

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      title: 'RUN OVER',
      showBack: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            run.opponentsBeaten > 0 ? 'SURVIVOR' : 'GOOD FIGHT',
            style: const TextStyle(
              color: BrawlerColors.cyan,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (isNewBest) ...[
            const SizedBox(height: 12),
            const Text(
              'NEW BEST!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BrawlerColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _stat('Opponents beaten', '${run.opponentsBeaten}'),
          _stat('Best run', '$best'),
          _stat('Fighter', '${run.player.name} (${run.player.signTitle})'),
          const SizedBox(height: 24),
          BigButton(
            'RUN AGAIN',
            onPressed: () => Navigator.of(context).pop('again'),
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
