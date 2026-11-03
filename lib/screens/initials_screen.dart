// Arcade-style initials entry (spec 4.6). Real: three letters picked with up/down arrows (no keyboard
// pop-up), letter stepping from HighScoreRules.stepLetter. Pops the 3 letters on SAVE, null on skip/back.
import 'package:flutter/material.dart';

import '../game/records.dart';
import 'brawler_ui.dart';

class InitialsScreen extends StatefulWidget {
  final int score;
  const InitialsScreen({super.key, required this.score});

  @override
  State<InitialsScreen> createState() => _InitialsScreenState();
}

class _InitialsScreenState extends State<InitialsScreen> {
  String _initials = 'AAA';

  void _step(int i, int d) =>
      setState(() => _initials = HighScoreRules.stepLetter(_initials, i, d));

  Widget _wheel(int i) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 64,
        height: 56,
        child: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_up,
            color: BrawlerColors.cyan,
            size: 40,
          ),
          onPressed: () => _step(i, 1),
        ),
      ),
      Container(
        width: 64,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BrawlerColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BrawlerColors.gold, width: 2),
        ),
        child: Text(
          _initials[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      SizedBox(
        width: 64,
        height: 56,
        child: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: BrawlerColors.cyan,
            size: 40,
          ),
          onPressed: () => _step(i, -1),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return BrawlerPage(
      title: 'NEW HIGH SCORE!',
      showBack: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.score}',
            style: const TextStyle(
              color: BrawlerColors.gold,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your initials',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _wheel(0),
                const SizedBox(width: 12),
                _wheel(1),
                const SizedBox(width: 12),
                _wheel(2),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BigButton(
            'SAVE',
            onPressed: () => Navigator.of(context).pop(_initials),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
