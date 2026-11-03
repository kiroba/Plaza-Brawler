// High-score board (spec 4.6). Real: top 10 from sqflite on this phone (HighScoreRepo), best first; the
// score just saved is highlighted. Local only: no online leaderboard.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/records.dart';
import 'brawler_ui.dart';

class HighScoresScreen extends StatefulWidget {
  /// ts of the entry to highlight (the one just saved), or null.
  final int? highlightTs;
  const HighScoresScreen({super.key, this.highlightTs});

  @override
  State<HighScoresScreen> createState() => _HighScoresScreenState();
}

class _HighScoresScreenState extends State<HighScoresScreen> {
  List<HighScoreEntry>? _rows;

  @override
  void initState() {
    super.initState();
    appState.highScores.top().then((r) {
      if (mounted) setState(() => _rows = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return BrawlerPage(
      title: 'HIGH SCORES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No scores yet. Be the first!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) _row(i + 1, rows[i]),
          const SizedBox(height: 16),
          BigButton('DONE', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Widget _row(int rank, HighScoreEntry e) {
    final hl = widget.highlightTs != null && e.ts == widget.highlightTs;
    final sign = e.sign.isEmpty
        ? ''
        : e.sign[0].toUpperCase() + e.sign.substring(1);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hl
            ? BrawlerColors.gold.withValues(alpha: 0.2)
            : BrawlerColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hl ? BrawlerColors.gold : Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: BrawlerColors.cyan,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            e.initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$sign · fight ${e.reached}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Text(
            '${e.score}',
            style: const TextStyle(
              color: BrawlerColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
