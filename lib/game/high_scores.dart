// High scores (spec 4.6): top 10 in sqflite table high_scores(id, initials, score, sign, reached, ts).
// Real: storage on this phone. Ranking rules are in records.dart. Each saved score is also signed as a
// local ARCADE_SCORE event by the caller (omniNode.dispatchEvent), never sent anywhere.
import 'package:sqflite/sqflite.dart';

import 'brawler_db.dart';
import 'records.dart';

class HighScoreRepo {
  final Future<Database> Function() _open;
  HighScoreRepo({Future<Database> Function()? open})
    : _open = open ?? (() => BrawlerDb.open());

  /// Top 10, best first. Never throws (empty on error).
  Future<List<HighScoreEntry>> top() async {
    try {
      final db = await _open();
      final rows = await db.query(
        'high_scores',
        orderBy: 'score DESC, ts ASC',
        limit: HighScoreRules.keep,
      );
      return [for (final r in rows) HighScoreEntry.fromRow(r)];
    } catch (_) {
      return [];
    }
  }

  Future<bool> qualifies(int score) async =>
      HighScoreRules.qualifies(score, await top());

  /// Saves a score and trims the table to the top 10. Returns the stored entry's rank (1-based) or 0.
  Future<int> add(HighScoreEntry e) async {
    try {
      final db = await _open();
      final clean = HighScoreEntry(
        initials: HighScoreRules.cleanInitials(e.initials),
        score: e.score,
        sign: e.sign,
        reached: e.reached,
        ts: e.ts,
      );
      final id = await db.insert('high_scores', clean.toRow());
      final all = [
        for (final r in await db.query('high_scores'))
          HighScoreEntry.fromRow(r),
      ];
      final keep = HighScoreRules.rank(all);
      final keepIds = keep.map((x) => x.id).whereType<int>().toList();
      if (keepIds.isNotEmpty) {
        await db.delete(
          'high_scores',
          where: 'id NOT IN (${List.filled(keepIds.length, '?').join(',')})',
          whereArgs: keepIds,
        );
      }
      final rank = keep.indexWhere((x) => x.id == id);
      return rank < 0 ? 0 : rank + 1;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final db = await _open();
      await db.delete('high_scores');
    } catch (_) {}
  }
}
