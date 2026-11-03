// OmniMindClient (spec 5.2) against package:http's MockClient: success -> manifest/FighterDef, and every
// failure (timeout, 400, malformed JSON, wrong envelope, refused connection) -> null / offline, never a throw.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plaza_brawler/net/omnimind_client.dart';
import 'package:test/test.dart';

/// A manifest shaped like daemon 8.26's zodiac_npc('scorpio', 7).
Map<String, dynamic> _manifest() => {
  'schema': 1,
  'kind': 'npc_manifest',
  'generator': 'omnimind-zodiac',
  'sign': 'scorpio',
  'seed': 7,
  'name': 'Vexora',
  'traits': {
    'sign': 'scorpio',
    'element': 'water',
    'modality': 'fixed',
    'archetype': 'shade',
    'temperament': ['intense', 'secretive', 'relentless'],
    'stats': {'power': 8, 'agility': 6, 'wit': 6, 'resolve': 8},
    'quirk': 'counts_stars',
  },
  'trait_hash': 'ab' * 32,
  'layers': [
    for (final l in ['body', 'palette', 'outfit', 'accessory', 'aura'])
      {
        'layer': l,
        'asset_id': '${l}_x',
        'z': ['body', 'palette', 'outfit', 'accessory', 'aura'].indexOf(l),
        'tint': '#5c1a33',
        'opacity': l == 'aura' ? 80 : 100,
      },
  ],
  'feed_injectable': false,
  'manifest_hash': '1234abcd' * 8,
};

OmniMindClient _with(
  Future<http.Response> Function(http.Request) h, {
  String? token,
  Duration timeout = const Duration(milliseconds: 1500),
}) => OmniMindClient(client: MockClient(h), token: token, timeout: timeout);

void main() {
  test(
    'success: GET generate-asset with sign, seed and Bearer -> manifest',
    () async {
      final seen = <http.Request>[];
      final c = _with((req) async {
        seen.add(req);
        return http.Response(
          jsonEncode({'status': 'success', 'data': _manifest()}),
          200,
        );
      }, token: 'tok');
      expect(c.statusLine(), omniMindOffline);
      final m = await c.generateNpc('Scorpio', 7);
      expect(m, isNotNull);
      expect(m!['name'], 'Vexora');
      expect(
        seen.single.url.toString(),
        'http://127.0.0.1:5000/api/v1/omnimind/generate-asset?sign=scorpio&seed=7',
      );
      expect(seen.single.headers['Authorization'], 'Bearer tok');
      expect(c.lastOk, isTrue);
      expect(c.statusLine(), omniMindOnline);
    },
  );

  test('no token -> no Authorization header', () async {
    String? auth = 'unset';
    final c = _with((req) async {
      auth = req.headers['Authorization'];
      return http.Response('{}', 200);
    });
    await c.generateNpc('aries', 1);
    expect(auth, isNull);
  });

  test(
    'npcFighter: manifest -> FighterDef (source omnimind, node stats)',
    () async {
      final c = _with(
        (_) async => http.Response(
          jsonEncode({'status': 'success', 'data': _manifest()}),
          200,
        ),
      );
      final f = await c.npcFighter('scorpio', 7);
      expect(f, isNotNull);
      expect(f!.source, 'omnimind');
      expect(f.name, 'Vexora');
      expect(f.stats.power, 8);
      expect(f.layers.length, 5);
      expect(OmniMindClient.chipFor(f), 'OmniMind');
    },
  );

  test(
    '400 (bad sign/seed) -> null, offline fighter, offline status',
    () async {
      final c = _with(
        (_) async => http.Response(
          jsonEncode({'status': 'error', 'message': "'sign' must be one of"}),
          400,
        ),
      );
      expect(await c.generateNpc('scorpio', 1), isNull);
      expect(c.lastOk, isFalse);
      final f = await c.npcFighter('scorpio', 1);
      expect(f!.source, 'offline');
      expect(f.name, 'Shade of Scorpio');
      expect(OmniMindClient.chipFor(f), 'Offline');
      expect(c.statusLine(), omniMindOffline);
    },
  );

  test('timeout -> null within the timeout, never throws', () async {
    final c = _with((_) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      return http.Response(
        jsonEncode({'status': 'success', 'data': _manifest()}),
        200,
      );
    }, timeout: const Duration(milliseconds: 100));
    final sw = Stopwatch()..start();
    expect(await c.generateNpc('scorpio', 7), isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
    expect((await c.npcFighter('scorpio', 7))!.source, 'offline');
  });

  test('default timeout is 1.5 s', () {
    expect(OmniMindClient().timeout, const Duration(milliseconds: 1500));
  });

  test('malformed JSON, wrong envelope, odd manifest, errors -> null / offline, never throws', () async {
    final bodies = <String>[
      '<html>not json',
      '',
      '[]',
      '{"status":"success"}',
      '{"status":"error","data":{}}',
      '{"status":"success","data":"x"}',
      '{"status":"success","data":{"name":"no traits"}}',
    ];
    for (final b in bodies) {
      final c = _with((_) async => http.Response(b, 200));
      expect(await c.generateNpc('aries', 0), isNull, reason: b);
      expect((await c.npcFighter('aries', 0))!.source, 'offline', reason: b);
    }
    // A success envelope whose manifest can't become a fighter (stats missing) falls back too.
    final bad = _manifest()..['traits'] = {'sign': 'scorpio'};
    final c2 = _with(
      (_) async =>
          http.Response(jsonEncode({'status': 'success', 'data': bad}), 200),
    );
    expect((await c2.npcFighter('scorpio', 7))!.source, 'offline');
    expect(c2.statusLine(), omniMindOffline);
    for (final h in <Future<http.Response> Function(http.Request)>[
      (_) async => throw http.ClientException('refused'),
      (_) async => throw const FormatException('x'),
      (_) async => throw TimeoutException('x'),
      (_) async => http.Response('{"status":"success"}', 404),
      (_) async => http.Response('{}', 401),
      (_) async => http.Response('{}', 500),
    ]) {
      expect(await _with(h).generateNpc('leo', 3), isNull);
    }
  });

  test(
    'unknown sign offline -> null fighter; seeds are made non-negative',
    () async {
      final c = _with((_) async => http.Response('{}', 400));
      expect(await c.npcFighter('ophiuchus', 1), isNull);
      expect(OmniMindClient.normalizeSeed(-1), 0);
      expect(OmniMindClient.normalizeSeed(-5), 4);
      expect(OmniMindClient.normalizeSeed(42), 42);
      expect(
        OmniMindClient().generateUri('Leo', -3).queryParameters['seed'],
        '2',
      );
    },
  );
}
