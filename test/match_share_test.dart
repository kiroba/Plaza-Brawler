// Match share stub (spec 5.3): saves locally, never claims a share.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plaza_brawler/net/match_share.dart';
import 'package:test/test.dart';

const _summary = {
  'mode': 'arcade',
  'winner': 'p1',
  'rounds': [{}, {}],
  'duration_ms': 61000,
  'p1': {'sign': 'aries', 'source': 'lpe'},
  'p2': {'sign': 'scorpio', 'source': 'omnimind'},
};

void main() {
  test('sharing off: saved locally, nothing sent', () async {
    final saved = <Map<String, dynamic>>[];
    var calls = 0;
    final s = MatchShare(
      saveLocal: (m) async {
        saved.add(m);
        return true;
      },
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(s.shareEnabled, isFalse); // default off
    expect(await s.shareMatch(_summary), ShareResult.savedLocalOnly);
    expect(saved.length, 1);
    expect(calls, 0);
    expect(s.statusLine(), matchShareStatus);
    expect(
      s.statusLine(),
      'Saved on this phone; sharing needs Omni Node 8.28+',
    );
    expect(MatchShare.words(ShareResult.nodeTooOld), matchShareStatus);
  });

  test('no saver or a failing saver -> notSaved, never throws', () async {
    expect(await MatchShare().shareMatch(_summary), ShareResult.notSaved);
    final boom = MatchShare(saveLocal: (_) async => throw StateError('db'));
    expect(await boom.shareMatch(_summary), ShareResult.notSaved);
    expect(
      await MatchShare(saveLocal: (_) async => false).shareMatch(_summary),
      ShareResult.notSaved,
    );
  });

  test('payload has the spec 5.3 fields', () {
    final p = MatchShare.payloadFrom(
      _summary,
      appVersion: '5.4.0',
      score: 1200,
    );
    expect(p, {
      'game': 'plaza_brawler',
      'mode': 'arcade',
      'p1_sign': 'aries',
      'p2_sign': 'scorpio',
      'p2_source': 'omnimind',
      'winner': 'p1',
      'rounds': 2,
      'score': 1200,
      'duration_ms': 61000,
      'app_version': '5.4.0',
    });
  });

  group('POST /api/games/match', () {
    late List<http.Request> reqs;
    MatchShare share(
      int status, {
      bool saved = true,
      String token = 'tok123',
      Duration? delay,
    }) {
      reqs = [];
      return MatchShare(
        saveLocal: (_) async => saved,
        shareEnabled: true,
        token: () => token,
        appVersion: '5.4.0',
        timeout: const Duration(milliseconds: 200),
        client: MockClient((r) async {
          reqs.add(r);
          if (delay != null) await Future<void>.delayed(delay);
          return http.Response(
            status == 200
                ? '{"status":"SUCCESS","event_id":"0xab","signed_by":"node","ts":1}'
                : '{"status":"ERROR"}',
            status,
          );
        }),
      );
    }

    test('200 -> shared; posts payloadFrom (not the raw summary) once, with the Bearer token', () async {
      final s = share(200);
      expect(await s.shareMatch(_summary, score: 1200), ShareResult.shared);
      expect(reqs, hasLength(1));
      final r = reqs.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'http://127.0.0.1:5000/api/games/match');
      expect(r.headers['Authorization'], 'Bearer tok123');
      expect(r.headers['Content-Type'], startsWith('application/json'));
      expect(
        jsonDecode(r.body),
        MatchShare.payloadFrom(_summary, appVersion: '5.4.0', score: 1200),
      );
      expect((jsonDecode(r.body) as Map).containsKey('p1'), isFalse);
      expect(s.nodeSupportsMatches, isTrue);
      expect(s.statusLine(), 'On: results go to Omni Node on this phone');
    });

    test('404 -> nodeTooOld, and later matches are not posted', () async {
      final s = share(404);
      expect(await s.shareMatch(_summary), ShareResult.nodeTooOld);
      expect(s.nodeSupportsMatches, isFalse);
      expect(await s.shareMatch(_summary), ShareResult.nodeTooOld);
      expect(reqs, hasLength(1));
    });

    for (final code in [400, 401, 411, 413, 429, 500, 503]) {
      test('$code -> savedLocalOnly, no retry', () async {
        final s = share(code);
        expect(await s.shareMatch(_summary), ShareResult.savedLocalOnly);
        expect(reqs, hasLength(1));
      });
    }

    test('no token -> no Authorization header', () async {
      final s = share(200, token: '');
      await s.shareMatch(_summary);
      expect(reqs.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'timeout / connection refused -> savedLocalOnly, never throws',
      () async {
        final slow = share(200, delay: const Duration(seconds: 1));
        expect(await slow.shareMatch(_summary), ShareResult.savedLocalOnly);
        final down = MatchShare(
          saveLocal: (_) async => true,
          shareEnabled: true,
          client: MockClient((_) async => throw const SocketLikeError()),
        );
        expect(await down.shareMatch(_summary), ShareResult.savedLocalOnly);
      },
    );

    test(
      'local save failed: shared still counts on 200, otherwise notSaved',
      () async {
        expect(
          await share(200, saved: false).shareMatch(_summary),
          ShareResult.shared,
        );
        expect(
          await share(500, saved: false).shareMatch(_summary),
          ShareResult.notSaved,
        );
        expect(
          await share(404, saved: false).shareMatch(_summary),
          ShareResult.notSaved,
        );
      },
    );

    test('resultFor maps the status codes', () {
      expect(MatchShare.resultFor(200, savedLocally: true), ShareResult.shared);
      expect(
        MatchShare.resultFor(404, savedLocally: true),
        ShareResult.nodeTooOld,
      );
      expect(
        MatchShare.resultFor(400, savedLocally: true),
        ShareResult.savedLocalOnly,
      );
      expect(
        MatchShare.resultFor(null, savedLocally: true),
        ShareResult.savedLocalOnly,
      );
      expect(
        MatchShare.resultFor(null, savedLocally: false),
        ShareResult.notSaved,
      );
    });
  });

  group('probe (node-health features)', () {
    MatchShare withHealth(int status, String body, {List<Uri>? seen}) =>
        MatchShare(
          token: () => 'tok',
          client: MockClient((r) async {
            seen?.add(r.url);
            return http.Response(body, status);
          }),
        );

    test('features has games_match -> true (GET :9100 node-health)', () async {
      final seen = <Uri>[];
      final s = withHealth(
        200,
        '{"status":"OK","features":["games_match"]}',
        seen: seen,
      );
      expect(await s.probe(), isTrue);
      expect(
        seen.single.toString(),
        'http://127.0.0.1:9100/api/v1/telemetry/node-health',
      );
    });

    test('older node (no features key) or other features -> false', () async {
      expect(
        await withHealth(200, '{"status":"OK","version":"8.27.0"}').probe(),
        isFalse,
      );
      expect(await withHealth(200, '{"features":["other"]}').probe(), isFalse);
      expect(
        await withHealth(200, '{"features":"games_match"}').probe(),
        isFalse,
      );
    });

    test(
      'no answer / bad JSON / 401 keeps the last known value (null at first)',
      () async {
        final s = MatchShare(
          client: MockClient((_) async => throw const SocketLikeError()),
        );
        expect(await s.probe(), isNull);
        s.nodeSupportsMatches = true;
        expect(await s.probe(), isTrue);
        expect(await withHealth(200, 'not json').probe(), isNull);
        expect(await withHealth(401, '{}').probe(), isNull);
      },
    );

    test('status line follows support and the switch', () async {
      final s = withHealth(200, '{"features":["games_match"]}');
      expect(s.statusLine(), matchShareStatus);
      await s.probe();
      expect(s.statusLine(), 'Off: results stay on this phone');
      s.shareEnabled = true;
      expect(s.statusLine(), 'On: results go to Omni Node on this phone');
    });
  });

  group('PvP envelope ingest (Nov 22 hardening)', () {
    const envelope = {
      'type': 'pvp_match',
      'payload': {
        'v': 1,
        'session_id': '0123456789abcdef0123456789abcdef',
        'seed': 42,
        'host_pubkey': 'aa',
        'guest_pubkey': 'bb',
        'p1_sign': 'aries',
        'p2_sign': 'scorpio',
        'winner': 'p1',
        'wins': [2, 0],
        'rounds': 2,
        'duration_ms': 61000,
        'final_state_hash': 'cc',
      },
      'signatures': {'host': 'dd', 'guest': 'ee'},
    };

    // Answers by body: envelope posts get [envStatus] (null = no answer),
    // delegate summary posts get [sumStatus].
    MatchShare pvpShare(
      List<http.Request> reqs, {
      required int? envStatus,
      int sumStatus = 200,
      List<ShareAttempt>? attempts,
    }) {
      return MatchShare(
        saveLocal: (_) async => true,
        shareEnabled: true,
        token: () => 'tok',
        appVersion: '5.4.0',
        onAttempt: attempts?.add,
        client: MockClient((r) async {
          reqs.add(r);
          final isEnvelope = (jsonDecode(r.body) as Map).containsKey('type');
          final code = isEnvelope ? envStatus : sumStatus;
          if (code == null) throw const SocketLikeError();
          return http.Response('{}', code);
        }),
      );
    }

    test('envelope 200 -> shared, one post, attempt recorded', () async {
      final reqs = <http.Request>[];
      final attempts = <ShareAttempt>[];
      final s = pvpShare(reqs, envStatus: 200, attempts: attempts);
      expect(await s.sharePvpMatch(envelope), ShareResult.shared);
      expect(reqs, hasLength(1));
      expect(attempts.single.gate, 'shared');
      expect(attempts.single.pvp, isTrue);
    });

    test('envelope 400 -> delegate summary fallback, sharedDelegate', () async {
      final reqs = <http.Request>[];
      final attempts = <ShareAttempt>[];
      final s = pvpShare(reqs, envStatus: 400, attempts: attempts);
      expect(await s.sharePvpMatch(envelope), ShareResult.sharedDelegate);
      expect(reqs, hasLength(2));
      expect(jsonDecode(reqs[1].body), {
        'game': 'plaza_brawler',
        'mode': 'pvp',
        'p1_sign': 'aries',
        'p2_sign': 'scorpio',
        'winner': 'p1',
        'rounds': 2,
        'duration_ms': 61000,
        'app_version': '5.4.0',
      });
      expect(attempts.single.gate, 'delegate');
      expect(attempts.single.envelopeStatus, 400);
      expect(attempts.single.httpStatus, 200);
      expect(
        MatchShare.words(ShareResult.sharedDelegate),
        'Shared with Omni Node (summary only)',
      );
    });

    test(
      'envelope 400, summary also refused -> savedLocalOnly, both codes kept',
      () async {
        final reqs = <http.Request>[];
        final attempts = <ShareAttempt>[];
        final s = pvpShare(
          reqs,
          envStatus: 400,
          sumStatus: 500,
          attempts: attempts,
        );
        expect(await s.sharePvpMatch(envelope), ShareResult.savedLocalOnly);
        expect(reqs, hasLength(2));
        expect(attempts.single.gate, 'http');
        expect(attempts.single.httpStatus, 500);
        expect(attempts.single.envelopeStatus, 400);
      },
    );

    test('envelope 401 -> NO fallback (same token gate)', () async {
      final reqs = <http.Request>[];
      final attempts = <ShareAttempt>[];
      final s = pvpShare(reqs, envStatus: 401, attempts: attempts);
      expect(await s.sharePvpMatch(envelope), ShareResult.savedLocalOnly);
      expect(reqs, hasLength(1));
      expect(attempts.single.gate, 'http');
      expect(attempts.single.httpStatus, 401);
      expect(attempts.single.describe(), contains('401'));
      expect(attempts.single.describe(), contains('token'));
    });

    test('no answer -> NO fallback (envelope may have landed)', () async {
      final reqs = <http.Request>[];
      final attempts = <ShareAttempt>[];
      final s = pvpShare(reqs, envStatus: null, attempts: attempts);
      expect(await s.sharePvpMatch(envelope), ShareResult.savedLocalOnly);
      expect(reqs, hasLength(1));
      expect(attempts.single.gate, 'noAnswer');
    });

    test('envelope 404 -> nodeTooOld, no fallback, support latched', () async {
      final reqs = <http.Request>[];
      final s = pvpShare(reqs, envStatus: 404);
      expect(await s.sharePvpMatch(envelope), ShareResult.nodeTooOld);
      expect(reqs, hasLength(1));
      expect(s.nodeSupportsMatches, isFalse);
    });

    test('sharing off -> nothing posted, attempt gate off', () async {
      final reqs = <http.Request>[];
      final attempts = <ShareAttempt>[];
      final s = MatchShare(
        saveLocal: (_) async => true,
        onAttempt: attempts.add,
        client: MockClient((r) async {
          reqs.add(r);
          return http.Response('{}', 200);
        }),
      );
      expect(await s.sharePvpMatch(envelope), ShareResult.savedLocalOnly);
      expect(reqs, isEmpty);
      expect(attempts.single.gate, 'off');
    });

    test('attempt encode/decode round-trips; garbage decodes to null', () {
      final a = ShareAttempt(
        pvp: true,
        gate: 'http',
        httpStatus: 401,
        at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final b = ShareAttempt.decode(a.encode())!;
      expect(b.pvp, isTrue);
      expect(b.gate, 'http');
      expect(b.httpStatus, 401);
      expect(b.envelopeStatus, isNull);
      expect(b.at.millisecondsSinceEpoch, 1700000000000);
      expect(ShareAttempt.decode(null), isNull);
      expect(ShareAttempt.decode('nonsense'), isNull);
      expect(ShareAttempt.decode('bogus|1|2|3|1'), isNull);
    });

    test('solo attempts are recorded too, and the status line names the code', () async {
      final attempts = <ShareAttempt>[];
      final s = MatchShare(
        saveLocal: (_) async => true,
        shareEnabled: true,
        onAttempt: attempts.add,
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      s.nodeSupportsMatches = true;
      expect(await s.shareMatch(_summary), ShareResult.savedLocalOnly);
      expect(attempts.single.pvp, isFalse);
      expect(attempts.single.gate, 'http');
      expect(attempts.single.httpStatus, 500);
      expect(s.statusLine(), contains('HTTP 500'));
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
