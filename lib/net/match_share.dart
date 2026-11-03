// Match sharing with Omni Node (spec 5.3), client stub. Pure Dart.
// Real: the match summary is saved on this phone through [MatchSaver] (the app passes
// omniNode.dispatchEvent('FIGHTER_MATCH_END', ...), a signed, hash-chained LocalEventStore entry).
// Stubbed: sharing. Omni Node has no POST /api/games/match yet, so nothing is sent and [ShareResult.shared]
// is never returned by this build. When the endpoint ships, POST here and map a 404 to nodeTooOld.

/// Saves one match summary locally; returns true when it was stored.
typedef MatchSaver = Future<bool> Function(Map<String, dynamic> summary);

enum ShareResult {
  /// Sent to Omni Node (not possible until the node has a game endpoint).
  shared,

  /// Saved on this phone only.
  savedLocalOnly,

  /// Sharing is on, but the node has no game endpoint yet (or answered 404).
  nodeTooOld,

  /// "Share my match results" is off (spec name; this build reports [savedLocalOnly] when the save worked).
  off,

  /// The local save itself failed.
  notSaved,
}

/// Settings line for "Sharing fights with Omni Node" until the daemon endpoint ships.
const String matchShareStatus =
    'Saved on this phone; sharing needs a newer Omni Node';

class MatchShare {
  /// Local save hook; null means nothing is stored (a no-op), reported as [ShareResult.notSaved].
  final MatchSaver? saveLocal;

  /// The Settings toggle "Share my match results" (default off).
  bool shareEnabled;

  MatchShare({this.saveLocal, this.shareEnabled = false});

  /// The summary that would go to POST /api/games/match (spec 5.3 payload), from MatchEngine.summary().
  static Map<String, dynamic> payloadFrom(
    Map<String, dynamic> summary, {
    required String appVersion,
    int? score,
  }) {
    Map p(String k) => summary[k] is Map ? summary[k] as Map : const {};
    return {
      'game': 'plaza_brawler',
      'mode': summary['mode'],
      'p1_sign': p('p1')['sign'],
      'p2_sign': p('p2')['sign'],
      'p2_source': p('p2')['source'],
      'winner': summary['winner'],
      'rounds': summary['rounds'] is List
          ? (summary['rounds'] as List).length
          : 0,
      if (score != null) 'score': score,
      'duration_ms': summary['duration_ms'],
      'app_version': appVersion,
    };
  }

  /// Saves [summary] on this phone and reports honestly what happened. Never throws, never fakes a share.
  Future<ShareResult> shareMatch(Map<String, dynamic> summary) async {
    var saved = false;
    try {
      saved = await (saveLocal?.call(summary) ?? Future.value(false));
    } catch (_) {
      saved = false;
    }
    if (!saved) return ShareResult.notSaved;
    // No game endpoint on any Omni Node yet: sharing on = node too old; off = local only.
    return shareEnabled ? ShareResult.nodeTooOld : ShareResult.savedLocalOnly;
  }

  /// One line for Settings / the run-end screen.
  String statusLine() => matchShareStatus;

  /// Plain words for a [ShareResult].
  static String words(ShareResult r) {
    switch (r) {
      case ShareResult.shared:
        return 'Shared with Omni Node';
      case ShareResult.savedLocalOnly:
      case ShareResult.nodeTooOld:
        return matchShareStatus;
      case ShareResult.off:
      case ShareResult.notSaved:
        return 'Match not saved';
    }
  }
}
