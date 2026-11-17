// PvP slice S3 — integrity + result tests (pure Dart, runs in the VM).
// The fake-transport tests drive two PvpLockstep drivers against each
// other and prove the 60-frame state-hash checkpoints agree in a clean
// match and abort both sides as a desync when a hash disagrees. The
// socket tests run a full scripted match over real S1 sessions and
// prove the dual-signed envelope: identical payload on both phones,
// both signatures verifying. The MatchShare tests prove the opt-in
// share gate for the envelope.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/net/match_share.dart';
import 'package:plaza_brawler/net/pvp_lockstep.dart';
import 'package:plaza_brawler/net/pvp_result.dart';
import 'package:plaza_brawler/net/pvp_session.dart';
import 'package:plaza_brawler/npc/zodiac_offline.dart';
import 'package:test/test.dart';

const _sessionId = '0123456789abcdef0123456789abcdef';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<({SimpleKeyPair pair, String pubkeyHex})> _newKey() async {
  final pair = await Ed25519().newKeyPair();
  final pub = await pair.extractPublicKey();
  return (pair: pair, pubkeyHex: _hex(pub.bytes));
}

Future<String> _sign(SimpleKeyPair pair, List<int> bytes) async {
  final sig = await Ed25519().sign(bytes, keyPair: pair);
  return _hex(sig.bytes);
}

MatchEngine _engine() => MatchEngine(
      p1: offlineFighter('aries')!,
      p2: offlineFighter('leo')!,
      seed: 42,
      mode: 'pvp',
    );

/// One end of a fake transport (the pvp_lockstep_test harness pattern):
/// [send] records and forwards to the peer; delivery is synchronous so
/// pump-by-pump tests are exact.
class _FakeEndpoint {
  final StreamController<PvpMessage> incoming =
      StreamController<PvpMessage>.broadcast(sync: true);
  final List<PvpMessage> sent = [];
  final Completer<void> _done = Completer<void>();
  _FakeEndpoint? peer;

  Future<void> get done => _done.future;

  void send(PvpMessage message) {
    sent.add(message);
    peer?._deliver(message);
  }

  void _deliver(PvpMessage message) => incoming.add(message);

  void inject(PvpMessage message) => _deliver(message);
}

(_FakeEndpoint, _FakeEndpoint) _pair() {
  final a = _FakeEndpoint();
  final b = _FakeEndpoint();
  a.peer = b;
  b.peer = a;
  return (a, b);
}

PvpLockstep _driverFor(_FakeEndpoint ep, {required bool isHost}) =>
    PvpLockstep(
      isHost: isHost,
      sessionId: _sessionId,
      messages: ep.incoming.stream,
      send: ep.send,
      done: ep.done,
    );

void main() {
  group('pvpMatchPayload', () {
    Map<String, dynamic> summary() => {
          'mode': 'pvp',
          'winner': 'p1',
          'wins': [2, 0],
          'rounds': [
            {'round': 1, 'winner': 'p1', 'ko': true},
            {'round': 2, 'winner': 'p1', 'ko': false},
          ],
          'duration_ms': 61000,
          'final_state_hash': 'ab' * 32,
        };

    Map<String, dynamic> build() => pvpMatchPayload(
          sessionId: _sessionId,
          seed: 1234,
          hostPubkey: '11' * 32,
          guestPubkey: '22' * 32,
          hostSign: 'aries',
          guestSign: 'leo',
          summary: summary(),
        );

    test('is canonical: identical inputs give byte-identical JSON', () {
      expect(pvpMatchCanonical(build()), pvpMatchCanonical(build()));
      // The fixed key order is the canonical form; pin its head so an
      // accidental reorder (which would break cross-phone signatures)
      // fails loudly here.
      expect(
        pvpMatchCanonical(build()),
        startsWith('{"v":1,"session_id":"$_sessionId","seed":1234,'),
      );
      expect(
        pvpResultBytes(build()),
        utf8.encode('pvp-result|${pvpMatchCanonical(build())}'),
      );
    });
  });

  group('S3 hash checkpoints over a fake transport', () {
    test('checkpoints agree past multiple 60-frame marks in a clean match',
        () {
      final (aEp, bEp) = _pair();
      final aEngine = _engine();
      final bEngine = _engine();
      final a = _driverFor(aEp, isHost: true)..attach(aEngine);
      final b = _driverFor(bEp, isHost: false)..attach(bEngine);

      for (var i = 0;
          i < 900 && (a.steppedFrames < 150 || b.steppedFrames < 150);
          i++) {
        a.pump(() => FighterIntent.none);
        b.pump(() => FighterIntent.none);
      }
      expect(a.steppedFrames, greaterThanOrEqualTo(150));
      expect(b.steppedFrames, greaterThanOrEqualTo(150));
      // Land both engines on the same frame before comparing states:
      // pump only the laggard, stepping on inputs the leader already
      // sampled and sent.
      for (var i = 0; i < 100 && a.steppedFrames != b.steppedFrames; i++) {
        if (a.steppedFrames < b.steppedFrames) {
          a.pump(() => FighterIntent.none);
        } else {
          b.pump(() => FighterIntent.none);
        }
      }
      expect(a.steppedFrames, b.steppedFrames);

      // Both sides actually sent checkpoint hashes at 60 and 120.
      for (final ep in [aEp, bEp]) {
        final frames = ep.sent
            .where((m) => m.type == PvpMessage.hash)
            .map((m) => m.data['frame'])
            .toSet();
        expect(frames, containsAll(<int>[60, 120]));
      }
      // And nobody cried desync: the engines stayed in lockstep.
      expect(a.desynced, isFalse);
      expect(b.desynced, isFalse);
      expect(a.aborted, isFalse);
      expect(b.aborted, isFalse);
      expect(aEngine.stateBytes(), bEngine.stateBytes());
    });

    test('a wrong peer hash aborts BOTH sides as a desync, no result', () {
      final (aEp, bEp) = _pair();
      final a = _driverFor(aEp, isHost: true)..attach(_engine());
      final b = _driverFor(bEp, isHost: false)..attach(_engine());
      for (var i = 0;
          i < 300 && (a.steppedFrames < 60 || b.steppedFrames < 60);
          i++) {
        a.pump(() => FighterIntent.none);
        b.pump(() => FighterIntent.none);
      }
      expect(a.steppedFrames, greaterThanOrEqualTo(60));

      // A forged checkpoint for frame 60 reaches A: A's own hash for
      // that frame disagrees, so A desyncs and tells B, which desyncs
      // too. A desynced match produces no envelope and is never stored
      // or shared — the lobby gates on exactly these flags.
      aEp.inject(
        const PvpMessage(PvpMessage.hash, _sessionId, {
          'frame': 60,
          'hash': 'deadbeef',
        }),
      );
      expect(a.desynced, isTrue);
      expect(a.aborted, isTrue);
      expect(a.abortReason, PvpLockstep.desyncReason);
      expect(a.abortReason, contains('no result recorded'));
      expect(b.desynced, isTrue);
      expect(b.aborted, isTrue);
      expect(b.abortReason, PvpLockstep.desyncReason);
    });
  });

  group('S3 result exchange over real sockets', () {
    Future<({PvpSession host, PvpSession guest, String hostPub, String guestPub, SimpleKeyPair hostPair, SimpleKeyPair guestPair})>
        connect() async {
      final hostKey = await _newKey();
      final guestKey = await _newKey();
      final host = await PvpHost.create(
        pubkeyHex: hostKey.pubkeyHex,
        sign: (bytes) => _sign(hostKey.pair, bytes),
        bindAddress: InternetAddress.loopbackIPv4,
      );
      addTearDown(host.close);
      final guestFuture = PvpGuest.connectManual(
        hostIp: '127.0.0.1',
        port: host.payload.port,
        code: host.sessionCode,
        pubkeyHex: guestKey.pubkeyHex,
        sign: (bytes) => _sign(guestKey.pair, bytes),
      );
      final hostSession = await host.waitForGuest();
      final guestSession = await guestFuture;
      addTearDown(hostSession.close);
      addTearDown(guestSession.close);
      return (
        host: hostSession,
        guest: guestSession,
        hostPub: hostKey.pubkeyHex,
        guestPub: guestKey.pubkeyHex,
        hostPair: hostKey.pair,
        guestPair: guestKey.pair,
      );
    }

    test(
      'a scripted full match ends with an identical dual-signed envelope',
      () async {
        final c = await connect();
        final hostStart = pvpExchangeStart(
          session: c.host,
          myPubkey: c.hostPub,
          mySign: 'aries',
          sign: (bytes) => _sign(c.hostPair, bytes),
        );
        final guestStart = pvpExchangeStart(
          session: c.guest,
          myPubkey: c.guestPub,
          mySign: 'leo',
          sign: (bytes) => _sign(c.guestPair, bytes),
        );
        final seed = (await hostStart).seed;
        await guestStart;

        final hostEngine = MatchEngine(
          p1: offlineFighter('aries')!,
          p2: offlineFighter('leo')!,
          seed: seed,
          mode: 'pvp',
        );
        final guestEngine = MatchEngine(
          p1: offlineFighter('aries')!,
          p2: offlineFighter('leo')!,
          seed: seed,
          mode: 'pvp',
        );
        final hostDriver = PvpLockstep.over(c.host)..attach(hostEngine);
        final guestDriver = PvpLockstep.over(c.guest)..attach(guestEngine);
        addTearDown(hostDriver.dispose);
        addTearDown(guestDriver.dispose);

        // The host walks in and swings until in range; the guest idles.
        // Test-only oracle: the sampler reads its own engine to decide.
        FighterIntent hostSampler() {
          if (hostEngine.phase != MatchPhase.fight) {
            return FighterIntent.none;
          }
          final gap = hostEngine.p2.x - hostEngine.p1.x;
          return gap > 55
              ? const FighterIntent(FighterIntent.right)
              : const FighterIntent(FighterIntent.hp);
        }

        for (var i = 0; i < 20000 && !hostEngine.isOver; i++) {
          hostDriver.pump(hostSampler);
          guestDriver.pump(() => FighterIntent.none);
          await Future<void>.delayed(Duration.zero);
        }
        expect(hostEngine.isOver, isTrue, reason: 'the scripted match ended');
        expect(guestEngine.isOver, isTrue);
        expect(hostDriver.desynced, isFalse);
        expect(guestDriver.desynced, isFalse);
        expect(hostEngine.stateBytes(), guestEngine.stateBytes());
        expect(hostEngine.matchWinner, 0); // the scripted host won

        // Each side builds the payload from its OWN summary, exactly as
        // the lobby does — identical because the engines never diverged.
        Map<String, dynamic> payloadFor(MatchEngine engine) =>
            pvpMatchPayload(
              sessionId: c.host.sessionId,
              seed: c.host.matchSeed,
              hostPubkey: c.hostPub,
              guestPubkey: c.guestPub,
              hostSign: 'aries',
              guestSign: 'leo',
              summary: engine.summary(),
            );
        final hostPayload = payloadFor(hostEngine);
        final guestPayload = payloadFor(guestEngine);
        expect(
          pvpMatchCanonical(hostPayload),
          pvpMatchCanonical(guestPayload),
        );
        expect(hostPayload['winner'], 'p1');
        expect(hostPayload['final_state_hash'], hostEngine.stateHash());

        final hostEnvelopeFuture = pvpExchangeResult(
          session: c.host,
          payload: hostPayload,
          sign: (bytes) => _sign(c.hostPair, bytes),
        );
        final guestEnvelopeFuture = pvpExchangeResult(
          session: c.guest,
          payload: guestPayload,
          sign: (bytes) => _sign(c.guestPair, bytes),
        );
        final hostEnvelope = await hostEnvelopeFuture;
        final guestEnvelope = await guestEnvelopeFuture;

        // Both phones hold the identical envelope, carrying BOTH
        // signatures, each verifying against the other's public key.
        expect(
          jsonEncode(hostEnvelope.toJson()),
          jsonEncode(guestEnvelope.toJson()),
        );
        expect(await hostEnvelope.verify(), isTrue);
        expect(await guestEnvelope.verify(), isTrue);
        expect(
          await pvpVerify(
            pvpResultBytes(hostPayload),
            hostEnvelope.guestSignature,
            c.guestPub,
          ),
          isTrue,
        );
        expect(
          await pvpVerify(
            pvpResultBytes(hostPayload),
            hostEnvelope.hostSignature,
            c.hostPub,
          ),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'payloads that differ (final hash) make the exchange throw — no envelope',
      () async {
        final c = await connect();
        Map<String, dynamic> payload(String hash) => pvpMatchPayload(
              sessionId: c.host.sessionId,
              seed: c.host.matchSeed,
              hostPubkey: c.hostPub,
              guestPubkey: c.guestPub,
              hostSign: 'aries',
              guestSign: 'leo',
              summary: {
                'winner': 'p1',
                'wins': [1, 0],
                'rounds': [
                  {'round': 1, 'winner': 'p1', 'ko': true},
                ],
                'duration_ms': 30000,
                'final_state_hash': hash,
              },
            );
        // The guest's view of the final state differs: its signature
        // covers different bytes than the host verifies against, and
        // vice versa. Both exchanges must fail, so neither side holds
        // an envelope to store or share.
        final hostFuture = pvpExchangeResult(
          session: c.host,
          payload: payload('aa' * 32),
          sign: (bytes) => _sign(c.hostPair, bytes),
        );
        final guestFuture = pvpExchangeResult(
          session: c.guest,
          payload: payload('bb' * 32),
          sign: (bytes) => _sign(c.guestPair, bytes),
        );
        final hostExpect = expectLater(hostFuture, throwsA(isA<PvpError>()));
        final guestExpect = expectLater(guestFuture, throwsA(isA<PvpError>()));
        await hostExpect;
        await guestExpect;
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('MatchShare.sharePvpMatch (the opt-in gate)', () {
    const envelope = {
      'type': 'pvp_match',
      'payload': {'v': 1, 'session_id': 'abc', 'winner': 'p1'},
      'signatures': {'host': 'h', 'guest': 'g'},
    };

    test('sharing off: envelope saved locally, no node call attempted',
        () async {
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
      expect(s.shareEnabled, isFalse); // default off, like solo sharing
      expect(await s.sharePvpMatch(envelope), ShareResult.savedLocalOnly);
      expect(saved, [envelope]);
      expect(calls, 0);
    });

    test('sharing on: exactly one POST of the envelope to /api/games/match',
        () async {
      final saved = <Map<String, dynamic>>[];
      final reqs = <http.Request>[];
      final s = MatchShare(
        saveLocal: (m) async {
          saved.add(m);
          return true;
        },
        shareEnabled: true,
        client: MockClient((req) async {
          reqs.add(req);
          return http.Response('{}', 200);
        }),
      );
      expect(await s.sharePvpMatch(envelope), ShareResult.shared);
      expect(saved, [envelope]);
      expect(reqs.length, 1);
      expect(reqs.single.method, 'POST');
      expect(reqs.single.url.path, '/api/games/match');
      expect(jsonDecode(reqs.single.body), envelope);
    });
  });
}
