// Plain records for high scores and feedback (spec 4.6, 4.8), plus the pure logic around them:
// top-10 ranking, initials, feedback tags, CSV export and the summary line. Pure Dart, no Flutter, no
// sqflite, so it is unit tested directly. Storage lives in high_scores.dart / feedback.dart.

class HighScoreEntry {
  final int? id;
  final String initials;
  final int score;
  final String sign;
  final int reached;
  final int ts;

  const HighScoreEntry({
    this.id,
    required this.initials,
    required this.score,
    required this.sign,
    required this.reached,
    required this.ts,
  });

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'initials': initials,
    'score': score,
    'sign': sign,
    'reached': reached,
    'ts': ts,
  };

  static HighScoreEntry fromRow(Map<String, Object?> r) => HighScoreEntry(
    id: r['id'] as int?,
    initials: (r['initials'] ?? '???').toString(),
    score: (r['score'] as num?)?.toInt() ?? 0,
    sign: (r['sign'] ?? '').toString(),
    reached: (r['reached'] as num?)?.toInt() ?? 0,
    ts: (r['ts'] as num?)?.toInt() ?? 0,
  );
}

class HighScoreRules {
  HighScoreRules._();
  static const int keep = 10;
  static const String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Best first; ties go to the earlier score.
  static List<HighScoreEntry> rank(Iterable<HighScoreEntry> all) {
    final l = all.toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.ts.compareTo(b.ts);
      });
    return l.length > keep ? l.sublist(0, keep) : l;
  }

  /// True when [score] would make the top 10 of [current].
  static bool qualifies(int score, List<HighScoreEntry> current) {
    if (score <= 0) return false;
    final top = rank(current);
    return top.length < keep || score > top.last.score;
  }

  /// Exactly three A-Z letters, upper case; anything else becomes 'AAA'-style padding.
  static String cleanInitials(String s) {
    final up = s.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    return '${up}AAA'.substring(0, 3);
  }

  /// Arcade-style letter wheel: step letter [i] of [initials] up (+1) or down (-1), wrapping.
  static String stepLetter(String initials, int i, int delta) {
    final s = cleanInitials(initials);
    final cur = letters.indexOf(s[i]);
    final next = letters[(cur + delta) % letters.length];
    return s.substring(0, i) + next + s.substring(i + 1);
  }
}

class FeedbackEntry {
  final int? id;
  final int stars;
  final List<String> tags;
  final String comment;
  final String mode;
  final String sign;
  final int reached;
  final int score;
  final String appVersion;
  final int ts;

  const FeedbackEntry({
    this.id,
    required this.stars,
    required this.tags,
    this.comment = '',
    required this.mode,
    required this.sign,
    this.reached = 0,
    this.score = 0,
    required this.appVersion,
    required this.ts,
  });

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'stars': stars,
    'tags': tags.join('|'),
    'comment': comment,
    'mode': mode,
    'sign': sign,
    'reached': reached,
    'score': score,
    'app_version': appVersion,
    'ts': ts,
  };

  static FeedbackEntry fromRow(Map<String, Object?> r) => FeedbackEntry(
    id: r['id'] as int?,
    stars: (r['stars'] as num?)?.toInt() ?? 0,
    tags: (r['tags'] ?? '')
        .toString()
        .split('|')
        .where((t) => t.isNotEmpty)
        .toList(),
    comment: (r['comment'] ?? '').toString(),
    mode: (r['mode'] ?? '').toString(),
    sign: (r['sign'] ?? '').toString(),
    reached: (r['reached'] as num?)?.toInt() ?? 0,
    score: (r['score'] as num?)?.toInt() ?? 0,
    appVersion: (r['app_version'] ?? '').toString(),
    ts: (r['ts'] as num?)?.toInt() ?? 0,
  );
}

class FeedbackRules {
  FeedbackRules._();
  static const tags = [
    'Too hard',
    'Too easy',
    'Confusing controls',
    'Fun',
    'Want more moves',
    'Laggy',
  ];
  static const maxTags = 3;
  static const maxComment = 140;

  /// Known tags only, at most 3, in the order picked.
  static List<String> cleanTags(Iterable<String> picked) {
    final out = <String>[];
    for (final t in picked) {
      if (tags.contains(t) && !out.contains(t)) out.add(t);
      if (out.length == maxTags) break;
    }
    return out;
  }

  /// One line, trimmed, capped (no names or device ids are ever added by the app).
  static String cleanComment(String s) {
    final one = s.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return one.length > maxComment ? one.substring(0, maxComment) : one;
  }

  static String _csvField(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(RegExp(r'[",\r\n]')) ||
        s.startsWith(' ') ||
        s.endsWith(' ')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static const csvHeader = [
    'id',
    'stars',
    'tags',
    'comment',
    'mode',
    'sign',
    'reached',
    'score',
    'app_version',
    'ts_iso',
  ];

  /// RFC 4180 CSV with a header row, CRLF line ends.
  static String toCsv(List<FeedbackEntry> rows) {
    final b = StringBuffer()
      ..write(csvHeader.join(','))
      ..write('\r\n');
    for (final r in rows) {
      final fields = [
        r.id ?? '',
        r.stars,
        r.tags.join('|'),
        r.comment,
        r.mode,
        r.sign,
        r.reached,
        r.score,
        r.appVersion,
        DateTime.fromMillisecondsSinceEpoch(
          r.ts,
          isUtc: true,
        ).toIso8601String(),
      ];
      b.write(fields.map(_csvField).join(','));
      b.write('\r\n');
    }
    return b.toString();
  }

  /// "N responses, avg X stars, top tags: a, b" (or "No responses yet").
  static String summary(List<FeedbackEntry> rows) {
    if (rows.isEmpty) return 'No responses yet';
    final avg = rows.map((r) => r.stars).reduce((a, b) => a + b) / rows.length;
    final counts = <String, int>{};
    for (final r in rows) {
      for (final t in r.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final top = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : tags.indexOf(a.key).compareTo(tags.indexOf(b.key));
      });
    final topTxt = top.isEmpty
        ? 'none'
        : top.take(3).map((e) => '${e.key} (${e.value})').join(', ');
    final n = rows.length;
    return '$n response${n == 1 ? '' : 's'}, avg ${avg.toStringAsFixed(1)} stars, top tags: $topTxt';
  }
}
