// Match sharing with Omni Node (spec 5.3). Pure Dart (package:http), never throws.
// Real: the match summary is always saved on this phone first through [MatchSaver] (the app passes
// omniNode.dispatchEvent('FIGHTER_MATCH_END', ...), a signed, hash-chained LocalEventStore entry). When
// "Share my match results" is on, [payloadFrom]'s bare summary (never the raw engine summary, which the node
// refuses with 400) is POSTed once to Omni Node's POST :5000/api/games/match (daemon 8.28.0+, Omni-Daemon
// Admin/docs/GAMES_MATCH.md) with "Authorization: Bearer <Omni Node token>", the same header lpe_client.dart
// sends. 200 -> shared, 404 -> nodeTooOld, anything else (no node, 400/401/413/429, timeout) -> saved on
// this phone only. No retries: the node doesn't de-duplicate bare posts, so a retry could store a match twice.
// [probe] reads "features" from GET :9100/api/v1/telemetry/node-health ("games_match" = supported; nodes
// before 8.28.0 have no features key) so Settings only enables the switch when the node can take results.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Saves one match summary locally; returns true when it was stored.
typedef MatchSaver = Future<bool> Function(Map<String, dynamic> summary);

enum ShareResult {
  /// Sent to Omni Node (POST /api/games/match answered 200).
  shared,

  /// Saved on this phone only (sharing off, no node, or the node refused/failed this post).
  savedLocalOnly,

  /// Sharing is on, but the node has no match endpoint (404: older than 8.28.0, or the probe said so).
  nodeTooOld,

  /// "Share my match results" is off (spec name; this build reports [savedLocalOnly] when the save worked).
  off,

  /// The local save failed and nothing was shared.
  notSaved,
}

/// Settings line for "Sharing fights with Omni Node" when the node can't take match results.
const String matchShareStatus =
    'Saved on this phone; sharing needs Omni Node 8.28+';

/// The capability name node-health lists when POST /api/games/match exists.
const String gamesMatchFeature = 'games_match';

class MatchShare {
  /// Local save hook; null means nothing is stored (a no-op), reported as [ShareResult.notSaved].
  final MatchSaver? saveLocal;

  /// The Settings toggle "Share my match results" (default off).
  bool shareEnabled;

  /// The Omni Node token at the time of the call ('' or null = send no Authorization header).
  final String? Function()? token;

  /// Sent as the payload's app_version.
  final String appVersion;

  final String host;
  final int ipcPort;
  final int telemetryPort;
  final Duration timeout;
  final http.Client? _client;

  /// What the last [probe] found: true = node lists games_match, false = it doesn't (or answered 404 to a
  /// post), null = not known yet (no probe, or the node didn't answer).
  bool? nodeSupportsMatches;

  /// The last [shareMatch] result, or null before the first match.
  ShareResult? lastResult;

  MatchShare({
    this.saveLocal,
    this.shareEnabled = false,
    this.token,
    this.appVersion = '',
    this.host = '127.0.0.1',
    this.ipcPort = 5000,
    this.telemetryPort = 9100,
    this.timeout = const Duration(seconds: 2),
    http.Client? client,
  }) : _client = client;

  Map<String, String> _headers({bool json = false}) {
    final t = token?.call();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
    };
  }

  /// Reads node-health's "features". Never throws. A node that answers without "features" (before 8.28.0)
  /// is false; no answer leaves the last known value (null at first) so a node that is just starting up
  /// doesn't flip the switch off for good.
  Future<bool?> probe() async {
    final c = _client ?? http.Client();
    try {
      final res = await c
          .get(
            Uri(
              scheme: 'http',
              host: host,
              port: telemetryPort,
              path: '/api/v1/telemetry/node-health',
            ),
            headers: _headers(),
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        if (res.statusCode == 404) nodeSupportsMatches = false;
        return nodeSupportsMatches;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final f = body is Map ? body['features'] : null;
      nodeSupportsMatches = f is List && f.contains(gamesMatchFeature);
    } catch (_) {
      // No node / timeout / not JSON: keep what we knew.
    } finally {
      if (_client == null) c.close();
    }
    return nodeSupportsMatches;
  }

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

  /// Saves [summary] on this phone, then (sharing on) POSTs [payloadFrom] once to the node. Reports
  /// honestly what happened. Never throws, never retries, never fakes a share.
  Future<ShareResult> shareMatch(
    Map<String, dynamic> summary, {
    int? score,
  }) async {
    var saved = false;
    try {
      saved = await (saveLocal?.call(summary) ?? Future.value(false));
    } catch (_) {
      saved = false;
    }
    final local = saved ? ShareResult.savedLocalOnly : ShareResult.notSaved;
    if (!shareEnabled) return lastResult = local;
    if (nodeSupportsMatches == false) {
      return lastResult = saved ? ShareResult.nodeTooOld : ShareResult.notSaved;
    }
    final code = await _post(
      payloadFrom(summary, appVersion: appVersion, score: score),
    );
    final r = resultFor(code, savedLocally: saved);
    if (code == 404) nodeSupportsMatches = false;
    if (code == 200) nodeSupportsMatches = true;
    return lastResult = r;
  }

  /// The share result for a POST /api/games/match status code (null = no answer).
  static ShareResult resultFor(int? statusCode, {required bool savedLocally}) {
    if (statusCode == 200) return ShareResult.shared;
    if (!savedLocally) return ShareResult.notSaved;
    if (statusCode == 404) return ShareResult.nodeTooOld;
    return ShareResult.savedLocalOnly;
  }

  /// One POST, status code or null. Never throws, never retries.
  Future<int?> _post(Map<String, dynamic> payload) async {
    final c = _client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri(
              scheme: 'http',
              host: host,
              port: ipcPort,
              path: '/api/games/match',
            ),
            headers: _headers(json: true),
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      return res.statusCode;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) c.close();
    }
  }

  /// One line for Settings ("Sharing fights with Omni Node").
  String statusLine() {
    if (nodeSupportsMatches != true) return matchShareStatus;
    if (!shareEnabled) return 'Off: results stay on this phone';
    switch (lastResult) {
      case ShareResult.savedLocalOnly:
        return 'On; the last match stayed on this phone (Omni Node didn\'t take it)';
      case ShareResult.notSaved:
        return 'On; the last match was not saved';
      default:
        return 'On: results go to Omni Node on this phone';
    }
  }

  /// Plain words for a [ShareResult].
  static String words(ShareResult r) {
    switch (r) {
      case ShareResult.shared:
        return 'Shared with Omni Node';
      case ShareResult.savedLocalOnly:
        return 'Saved on this phone';
      case ShareResult.nodeTooOld:
        return matchShareStatus;
      case ShareResult.off:
      case ShareResult.notSaved:
        return 'Match not saved';
    }
  }
}
