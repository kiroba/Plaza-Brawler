// OmniMind opponents from Omni Node, daemon v8.26.0+ (Omni-Daemon Admin/omni_omnimind.py, spec 5.2).
// Real: GET :5000/api/v1/omnimind/generate-asset?sign=&seed= -> {"status":"success","data": manifest}, computed
// on the node (nothing written to the chain; 400 for a bad sign or seed). Same package:http + Bearer token
// pattern as lpe_client.dart, 1.5 s timeout, never throws. With no node (or an older one) the opponent is the
// offline zodiac fighter (source 'offline'). Pure Dart (no Flutter), so it is unit tested with MockClient.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../game/fighter.dart';
import '../npc/zodiac_offline.dart';

/// Settings / VS-splash lines (spec 5.2). Only [omniMindOnline] after a real manifest came back.
const String omniMindOnline = 'OmniMind on Omni Node: generating opponents';
const String omniMindOffline = 'Offline opponents (Omni Node 8.26+ not found)';

/// The daemon accepts seeds 0..2^53 written as 1-16 digits; anything else is a 400.
const int omniMindMaxSeed = 9007199254740992; // 2^53

class OmniMindClient {
  final String host;
  final int ipcPort;
  final String? token;
  final Duration timeout;
  final http.Client? _client;

  /// True after the last [generateNpc] got a manifest, false after it failed, null before the first call.
  bool? lastOk;

  OmniMindClient({
    this.host = '127.0.0.1',
    this.ipcPort = 5000,
    this.token,
    this.timeout = const Duration(milliseconds: 1500),
    http.Client? client,
  }) : _client = client;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// A seed the daemon accepts: non-negative and at most 2^53 (negative ints are folded, not rejected).
  static int normalizeSeed(int seed) {
    final s = seed < 0 ? -(seed + 1) : seed;
    return s % (omniMindMaxSeed + 1);
  }

  Uri generateUri(String sign, int seed) => Uri(
    scheme: 'http',
    host: host,
    port: ipcPort,
    path: '/api/v1/omnimind/generate-asset',
    queryParameters: {
      'sign': sign.trim().toLowerCase(),
      'seed': '${normalizeSeed(seed)}',
    },
  );

  /// The node's NPC manifest for [sign] + [seed], or null (no node, node < 8.26, token refused, 400 for a bad
  /// sign/seed, timeout, or a reply that isn't a success envelope with a manifest). Never throws.
  Future<Map<String, dynamic>?> generateNpc(String sign, int seed) async {
    final c = _client ?? http.Client();
    Map<String, dynamic>? out;
    try {
      final res = await c
          .get(generateUri(sign, seed), headers: _headers)
          .timeout(timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map &&
            body['status'] == 'success' &&
            body['data'] is Map &&
            (body['data'] as Map)['traits'] is Map) {
          out = Map<String, dynamic>.from(body['data'] as Map);
        }
      }
    } catch (_) {
      out = null;
    } finally {
      if (_client == null) c.close();
    }
    lastOk = out != null;
    return out;
  }

  /// The opponent for [sign] + [seed]: built from the node's manifest (source 'omnimind') when OmniMind
  /// answered with a usable one, else the fixed offline fighter (source 'offline'). Null only for a sign
  /// that isn't one of the 12. Never throws.
  Future<FighterDef?> npcFighter(String sign, int seed) async {
    final m = await generateNpc(sign, seed);
    final f = m == null ? null : fighterFromManifest(m);
    if (f != null) return f;
    if (m != null)
      lastOk =
          false; // a manifest we couldn't use is not "generating opponents"
    return offlineFighter(sign);
  }

  /// One line for Settings: whether opponents come from OmniMind or the offline table.
  String statusLine() => lastOk == true ? omniMindOnline : omniMindOffline;

  /// VS-splash chip text for a fighter.
  static String chipFor(FighterDef f) =>
      f.source == 'omnimind' ? 'OmniMind' : 'Offline';
}
