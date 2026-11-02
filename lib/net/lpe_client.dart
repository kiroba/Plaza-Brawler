// Live Persona Engine (LPE) on Omni Node, daemon v8.25.0+ (Omni-Daemon Admin/docs/LPE_API.md).
//
// GET :5000/api/lpe/profile?pubkey=  -> this player's signed avatar profile, aura tier, XP
// GET :5000/api/lpe/plaza?viewer=    -> every avatar the node knows (used to pick a real opponent)
//
// Omni-Core-UI v0.1.0's OmniHubClient has no public generic GET, so this uses package:http with the
// same token header OmniHubClient sends ("Authorization: Bearer <Omni Node token>", accepted on
// loopback since daemon v8.20.0). Every call is read-only and never throws: any failure returns
// null and the game keeps its offline personas.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Label for the LPE when the node is missing, older than 8.25.0, or has no profile for this key.
const String needsNode825 = 'Needs Omni Node 8.25+';

class LpeClient {
  final String host;
  final int ipcPort;
  final String? token;
  final Duration timeout;
  final http.Client? _client;

  LpeClient({
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

  Uri _uri(String path, Map<String, String> query) => Uri(
      scheme: 'http',
      host: host,
      port: ipcPort,
      path: path,
      queryParameters: query.isEmpty ? null : query);

  /// (status code, decoded JSON object) or null when the node didn't answer with JSON.
  Future<(int, Map<String, dynamic>)?> _get(String path, Map<String, String> query) async {
    final c = _client ?? http.Client();
    try {
      final res = await c.get(_uri(path, query), headers: _headers).timeout(timeout);
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body is Map<String, dynamic> ? (res.statusCode, body) : null;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) c.close();
    }
  }

  /// This key's LPE profile view (`profile` object of the reply), or null (no node, node < 8.25,
  /// token refused, or no LPE profile for this key yet).
  Future<Map<String, dynamic>?> profile(String pubkey) async {
    if (pubkey.isEmpty) return null;
    final r = await _get('/api/lpe/profile', {'pubkey': pubkey, 'viewer': pubkey});
    if (r == null || r.$1 != 200) return null;
    final p = r.$2['profile'];
    return p is Map<String, dynamic> ? p : null;
  }

  /// Avatars the node knows (newest first), or null when the node has no LPE API.
  Future<List<Map<String, dynamic>>?> plaza({String? viewer, int limit = 50}) async {
    final r = await _get('/api/lpe/plaza', {
      'limit': '$limit',
      if (viewer != null && viewer.isNotEmpty) 'viewer': viewer,
    });
    if (r == null || r.$1 != 200 || r.$2['avatars'] is! List) return null;
    return (r.$2['avatars'] as List).whereType<Map<String, dynamic>>().toList();
  }
}

/// A fighter persona (the map the game screens read) built from an LPE avatar view.
/// [base] supplies what the LPE doesn't have yet (stats, behaviour weights).
Map<String, dynamic> personaFromLpe(Map<String, dynamic> avatar, Map<String, dynamic> base) {
  final aura = avatar['aura'] is Map ? Map<String, dynamic>.from(avatar['aura'] as Map) : <String, dynamic>{};
  final handle = (avatar['handle_display'] ?? avatar['handle'] ?? 'unknown').toString();
  final tier = (aura['tier'] ?? 'CITIZEN').toString();
  final auraHex = (aura['aura_color_hex'] ?? base['aura_hex'] ?? '#3A86EF').toString();
  final glowHex = (aura['secondary_glow_hex'] ?? auraHex).toString();
  final pubkey = (avatar['pubkey'] ?? '').toString();
  return {
    ...base,
    'persona_id': 'lpe_${pubkey.length >= 12 ? pubkey.substring(0, 12) : pubkey}',
    'archetype': '$handle · $tier',
    'name': handle,
    'handle': handle,
    'pubkey': pubkey,
    'tier': tier,
    'aura_hex': auraHex,
    'palette': [auraHex, glowHex, base['palette'] is List && (base['palette'] as List).length > 2
        ? (base['palette'] as List)[2]
        : '#FFD700'],
    'xp': avatar['xp'] ?? 0,
    'vibe_count': avatar['vibe_count'] ?? 0,
    'cosmetics': avatar['cosmetics'] ?? const [],
    'source': 'omni_node',
  };
}

/// The first plaza avatar that isn't [selfPubkey] and may interact with the public plaza, or null.
Map<String, dynamic>? pickOpponent(List<Map<String, dynamic>> avatars, String selfPubkey) {
  for (final a in avatars) {
    if (a['pubkey'] == selfPubkey) continue;
    final q = a['quarantine'];
    if (q is Map && q['can_interact_with_public'] == false) continue;
    return a;
  }
  return null;
}
