// Post-match feedback (spec 4.8): stars + up to 3 tags + an optional one-line comment, saved in sqflite
// table feedback(...). No names, no device ids. Real: storage, CSV export via the platform share sheet
// (share_plus), and the "N responses, avg X stars, top tags" summary.
import 'dart:convert';

import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'brawler_db.dart';
import 'records.dart';

class FeedbackRepo {
  final Future<Database> Function() _open;
  FeedbackRepo({Future<Database> Function()? open})
    : _open = open ?? (() => BrawlerDb.open());

  Future<bool> add(FeedbackEntry e) async {
    try {
      final db = await _open();
      final clean = FeedbackEntry(
        stars: e.stars.clamp(1, 5).toInt(),
        tags: FeedbackRules.cleanTags(e.tags),
        comment: FeedbackRules.cleanComment(e.comment),
        mode: e.mode,
        sign: e.sign,
        reached: e.reached,
        score: e.score,
        appVersion: e.appVersion,
        ts: e.ts,
      );
      await db.insert('feedback', clean.toRow());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FeedbackEntry>> all() async {
    try {
      final db = await _open();
      return [
        for (final r in await db.query('feedback', orderBy: 'ts ASC'))
          FeedbackEntry.fromRow(r),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<String> summary() async => FeedbackRules.summary(await all());

  Future<String> csv() async => FeedbackRules.toCsv(await all());

  /// Opens the share sheet with plaza_brawler_feedback.csv. Returns false when there is nothing to share
  /// or the platform refused.
  Future<bool> shareCsv() async {
    final rows = await all();
    if (rows.isEmpty) return false;
    try {
      final bytes = utf8.encode(FeedbackRules.toCsv(rows));
      await SharePlus.instance.share(
        ShareParams(
          title: 'Plaza Brawler feedback',
          subject: 'Plaza Brawler playtest feedback (${rows.length} responses)',
          files: [XFile.fromData(bytes, mimeType: 'text/csv')],
          fileNameOverrides: const ['plaza_brawler_feedback.csv'],
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final db = await _open();
      await db.delete('feedback');
    } catch (_) {}
  }
}
