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
// PvP (S3) reuses this class unchanged in shape: [sharePvpMatch] stores the dual-signed pvp_match
// envelope through the same saver and POSTs it through the same route when sharing is on.
// Ingest hardening (Nov 22, 2026): every share attempt is recorded as a [ShareAttempt] — which gate
// stopped it, and the HTTP status the node actually answered — and the app persists it, so a share
// that didn't land can be diagnosed after the fact instead of collapsing into "Saved on this phone".
// When the node refuses the envelope itself (400: it validated and said no), [sharePvpMatch] falls
// back ONCE to the daemon's delegate shape — the bare summary of [delegateSummaryFrom], node-signed —
// so the result still lands and counts; the dual-signed envelope stays in this phone's local log.
// No fallback on 401 (the same token gate would refuse the summary too) or on no-answer (the
// envelope may have landed despite the timeout, and bare posts are not de-duplicated).
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Saves one match summary locally; returns true when it was stored.
typedef MatchSaver = Future<bool> Function(Map<String, dynamic> summary);

enum ShareResult {
  /// Sent to Omni Node (POST /api/games/match answered 200).
  shared,

  /// The node refused the dual-signed PvP envelope (400) but took the bare summary instead
  /// (delegate shape, node-signed): the result counts on the node; the signatures stay local.
  sharedDelegate,

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

/// One share attempt, as evidence: which gate it reached and what the node answered.
/// Persisted by the app (see [encode]/[decode]) so the last attempt survives a restart
/// and Settings can say what actually happened instead of guessing.
class ShareAttempt {
  /// True for a PvP envelope share, false for a solo summary share.
  final bool pvp;

  /// shared | delegate | off | tooOld | http | noAnswer | notSaved
  final String gate;

  /// The decisive HTTP status, when the node answered at all.
  final int? httpStatus;

  /// For a PvP attempt that fell back: the status the ENVELOPE post got (the fallback's
  /// own answer is [httpStatus]).
  final int? envelopeStatus;

  final DateTime at;

  const ShareAttempt({
    required this.pvp,
    required this.gate,
    this.httpStatus,
    this.envelopeStatus,
    required this.at,
  });

  /// Honest one-liner for Settings.
  String describe() {
    switch (gate) {
      case 'shared':
        return 'Shared with Omni Node.';
      case 'delegate':
        return 'Omni Node refused the signed envelope (${envelopeStatus ?? 400}); '
            'the result went as a summary and counts. Signatures stay on this phone.';
      case 'off':
        return 'Saved on this phone — sharing is off.';
      case 'tooOld':
        return 'Saved on this phone — this Omni Node has no match endpoint (needs 8.28+).';
      case 'http':
        if (httpStatus == 401) {
          return 'Omni Node refused the share (401) — the node token is missing or '
              'wrong. Saved on this phone.';
        }
        return 'Omni Node refused the share (HTTP $httpStatus). Saved on this phone.';
      case 'noAnswer':
        return 'Omni Node didn\'t answer — saved on this phone.';
      default:
        return 'The last match was not saved.';
    }
  }

  String encode() =>
      '$gate|${httpStatus ?? ''}|${envelopeStatus ?? ''}|${at.millisecondsSinceEpoch}|${pvp ? 1 : 0}';

  static ShareAttempt? decode(String? s) {
    if (s == null) return null;
    final parts = s.split('|');
    if (parts.length != 5) return null;
    const gates = {
      'shared',
      'delegate',
      'off',
      'tooOld',
      'http',
      'noAnswer',
      'notSaved',
    };
    if (!gates.contains(parts[0])) return null;
    final ms = int.tryParse(parts[3]);
    if (ms == null) return null;
    return ShareAttempt(
      pvp: parts[4] == '1',
      gate: parts[0],
      httpStatus: int.tryParse(parts[1]),
      envelopeStatus: int.tryParse(parts[2]),
      at: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}

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

  /// The last share attempt's evidence (gate + the node's answer), or null before
  /// the first match. The app may seed this from storage at boot and persists every
  /// new attempt through [onAttempt].
  ShareAttempt? lastAttempt;

  /// Called with each new [ShareAttempt] as it is recorded (the app persists it).
  final void Function(ShareAttempt attempt)? onAttempt;

  MatchShare({
    this.saveLocal,
    this.shareEnabled = false,
    this.token,
    this.onAttempt,
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

  /// Records one share attempt as evidence and hands it to [onAttempt].
  void _record({
    required bool pvp,
    required String gate,
    int? httpStatus,
    int? envelopeStatus,
  }) {
    final a = ShareAttempt(
      pvp: pvp,
      gate: gate,
      httpStatus: httpStatus,
      envelopeStatus: envelopeStatus,
      at: DateTime.now(),
    );
    lastAttempt = a;
    onAttempt?.call(a);
  }

  /// The delegate (bare summary, node-signed) form of a PvP [envelope]: exactly the
  /// fields POST /api/games/match's summary shape accepts, taken from the envelope's
  /// payload. Posted once, as the fallback when the node refuses the envelope (400).
  static Map<String, dynamic> delegateSummaryFrom(
    Map<String, dynamic> envelope, {
    required String appVersion,
  }) {
    final p = envelope['payload'] is Map
        ? envelope['payload'] as Map
        : const {};
    return {
      'game': 'plaza_brawler',
      'mode': 'pvp',
      'p1_sign': p['p1_sign'],
      'p2_sign': p['p2_sign'],
      'winner': p['winner'],
      'rounds': p['rounds'],
      'duration_ms': p['duration_ms'],
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
    if (!shareEnabled) {
      _record(pvp: false, gate: saved ? 'off' : 'notSaved');
      return lastResult = local;
    }
    if (nodeSupportsMatches == false) {
      _record(pvp: false, gate: saved ? 'tooOld' : 'notSaved');
      return lastResult = saved ? ShareResult.nodeTooOld : ShareResult.notSaved;
    }
    final code = await _post(
      payloadFrom(summary, appVersion: appVersion, score: score),
    );
    final r = resultFor(code, savedLocally: saved);
    if (code == 404) nodeSupportsMatches = false;
    if (code == 200) nodeSupportsMatches = true;
    _record(
      pvp: false,
      gate: code == 200
          ? 'shared'
          : !saved
          ? 'notSaved'
          : code == 404
          ? 'tooOld'
          : code == null
          ? 'noAnswer'
          : 'http',
      httpStatus: code,
    );
    return lastResult = r;
  }

  /// PvP slice S3: stores a completed dual-signed [envelope] (the
  /// pvp_match JSON from pvp_result.dart) on this phone through the same
  /// [saveLocal] hook solo matches use, then — sharing on only — POSTs
  /// the envelope once to POST /api/games/match, the same route, headers
  /// and one-shot/no-retry discipline as [shareMatch]. A desynced or
  /// aborted match never reaches this call: no envelope exists for it.
  /// Never throws. Every outcome is recorded as a [ShareAttempt]; an
  /// envelope the node refuses with 400 falls back once to the delegate
  /// summary ([delegateSummaryFrom]) so the result still lands.
  Future<ShareResult> sharePvpMatch(Map<String, dynamic> envelope) async {
    var saved = false;
    try {
      saved = await (saveLocal?.call(envelope) ?? Future.value(false));
    } catch (_) {
      saved = false;
    }
    final local = saved ? ShareResult.savedLocalOnly : ShareResult.notSaved;
    if (!shareEnabled) {
      _record(pvp: true, gate: saved ? 'off' : 'notSaved');
      return lastResult = local;
    }
    if (nodeSupportsMatches == false) {
      _record(pvp: true, gate: saved ? 'tooOld' : 'notSaved');
      return lastResult = saved ? ShareResult.nodeTooOld : ShareResult.notSaved;
    }
    final code = await _post(envelope);
    if (code == 200) {
      nodeSupportsMatches = true;
      _record(pvp: true, gate: 'shared', httpStatus: code);
      return lastResult = ShareResult.shared;
    }
    if (code == 404) {
      nodeSupportsMatches = false;
      _record(
        pvp: true,
        gate: saved ? 'tooOld' : 'notSaved',
        httpStatus: code,
      );
      return lastResult = saved ? ShareResult.nodeTooOld : ShareResult.notSaved;
    }
    if (code == 400) {
      // The node validated the envelope and refused IT — the one failure the
      // delegate shape can cure. One fallback post of the bare summary; the
      // dual-signed envelope stays in this phone's local log either way.
      final dcode = await _post(
        delegateSummaryFrom(envelope, appVersion: appVersion),
      );
      if (dcode == 200) {
        nodeSupportsMatches = true;
        _record(
          pvp: true,
          gate: 'delegate',
          httpStatus: dcode,
          envelopeStatus: code,
        );
        return lastResult = ShareResult.sharedDelegate;
      }
      _record(
        pvp: true,
        gate: !saved
            ? 'notSaved'
            : dcode == null
            ? 'noAnswer'
            : 'http',
        httpStatus: dcode,
        envelopeStatus: code,
      );
      return lastResult = local;
    }
    _record(
      pvp: true,
      gate: !saved
          ? 'notSaved'
          : code == null
          ? 'noAnswer'
          : 'http',
      httpStatus: code,
    );
    return lastResult = local;
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
      case ShareResult.sharedDelegate:
        return 'On; the last match reached Omni Node as a summary (signed envelope refused)';
      case ShareResult.savedLocalOnly:
        final a = lastAttempt;
        if (a != null && a.gate == 'http') {
          return 'On; Omni Node refused the last match (HTTP ${a.httpStatus}) — saved on this phone';
        }
        if (a != null && a.gate == 'noAnswer') {
          return 'On; Omni Node didn\'t answer the last share — saved on this phone';
        }
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
      case ShareResult.sharedDelegate:
        return 'Shared with Omni Node (summary only)';
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
