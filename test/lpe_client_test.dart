import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plaza_brawler/net/lpe_client.dart';

const _me = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';
const _bob = 'bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22';
const _jail = 'cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33cc33';

Map<String, dynamic> _avatar(String pk, String handle, {bool jailed = false}) => {
      'pubkey': pk,
      'handle': handle,
      'handle_display': '@$handle.${pk.substring(0, 4)}',
      'aura': {'tier': 'CITIZEN', 'aura_color_hex': '#3A86EF', 'secondary_glow_hex': '#4CC9F0'},
      'quarantine': {'can_interact_with_public': !jailed},
      'xp': 120,
      'vibe_count': 2,
      'cosmetics': ['head_socket_crown'],
    };

void main() {
  test('reads profile and plaza with the Bearer token', () async {
    final seen = <http.Request>[];
    final client = MockClient((req) async {
      seen.add(req);
      if (req.url.path == '/api/lpe/profile') {
        return http.Response(jsonEncode({'status': 'OK', 'profile': _avatar(_me, 'kiro')}), 200);
      }
      return http.Response(
          jsonEncode({'status': 'OK', 'avatars': [_avatar(_me, 'kiro'), _avatar(_jail, 'jail', jailed: true), _avatar(_bob, 'bob')]}),
          200);
    });
    final lpe = LpeClient(token: 'tok', client: client);
    final p = await lpe.profile(_me);
    expect(p!['handle'], 'kiro');
    final plaza = await lpe.plaza(viewer: _me);
    expect(plaza!.length, 3);
    expect(pickOpponent(plaza, _me)!['pubkey'], _bob);
    expect(seen.first.headers['Authorization'], 'Bearer tok');
    expect(seen.first.url.toString(), 'http://127.0.0.1:5000/api/lpe/profile?pubkey=$_me&viewer=$_me');
    expect(seen.last.url.queryParameters['viewer'], _me);
  });

  test('older node, no profile, refused token or no node -> null (offline fallback)', () async {
    for (final code in [404, 401, 403, 500]) {
      final lpe = LpeClient(client: MockClient((_) async => http.Response('{"status":"ERROR"}', code)));
      expect(await lpe.profile(_me), isNull, reason: '$code');
      expect(await lpe.plaza(), isNull, reason: '$code');
    }
    final down = LpeClient(client: MockClient((_) async => throw http.ClientException('refused')));
    expect(await down.profile(_me), isNull);
    final html = LpeClient(client: MockClient((_) async => http.Response('<html>', 200)));
    expect(await html.plaza(), isNull);
    expect(await LpeClient(client: MockClient((_) async => http.Response('{}', 200))).profile(''), isNull);
  });

  test('persona keeps the offline fight stats and is labelled omni_node', () {
    const base = {
      'archetype': 'ZODIAC_ARIES',
      'palette': ['#FF3300', '#FF8800', '#FFD700'],
      'stats': {'str': 16},
      'source': 'offline',
    };
    final p = personaFromLpe(_avatar(_me, 'kiro'), base);
    expect(p['source'], 'omni_node');
    expect(p['stats'], {'str': 16});
    expect(p['archetype'], '@kiro.aa11 · CITIZEN');
    expect(p['palette'], ['#3A86EF', '#4CC9F0', '#FFD700']);
    expect(p['persona_id'], 'lpe_aa11aa11aa11');
    expect(pickOpponent([_avatar(_me, 'kiro')], _me), isNull);
    expect(needsNode825, 'Needs Omni Node 8.25+');
  });
}
