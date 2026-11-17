// PvP slice S2 — lockstep tests (pure Dart, runs in the VM).
// Unit tests drive PvpLockstep over a fake in-memory transport; the
// integration test runs two real S1 sessions over loopback sockets, two
// drivers and two engines, and proves both engines land in identical
// states after ~300 frames of scripted inputs.
import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:plaza_brawler/game/input.dart';
import 'package:plaza_brawler/game/match_engine.dart';
import 'package:plaza_brawler/net/pvp_lockstep.dart';
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

/// One end of a fake transport: [send] records and forwards to the peer
/// (unless [dropWhen] eats the message); [inject] delivers as if from
/// the peer. Delivery is synchronous so pump-by-pump tests are exact.
class _FakeEndpoint {
  final StreamController<PvpMessage> incoming =
      StreamController<PvpMessage>.broadcast(sync: true);
  final List<PvpMessage> sent = [];
  final List<PvpMessage> received = [];
  final Completer<void> _done = Completer<void>();
  _FakeEndpoint? peer;
  bool Function(PvpMessage message)? dropWhen;

  Future<void> get done => _done.future;

  void send(PvpMessage message) {
    sent.add(message);
    if (dropWhen?.call(message) ?? false) return;
    peer?._deliver(message);
  }

  void _deliver(PvpMessage message) {
    received.add(message);
    incoming.add(message);
  }

  void inject(PvpMessage message) => _deliver(message);

  void close() {
    if (!_done.isCompleted) _done.complete();
  }
}

(_FakeEndpoint, _FakeEndpoint) _pair() {
  final a = _FakeEndpoint();
  final b = _FakeEndpoint();
  a.peer = b;
  b.peer = a;
  return (a, b);
}

PvpLockstep _driverFor(
  _FakeEndpoint ep, {
  required bool isHost,
  DateTime Function()? clock,
}) =>
    PvpLockstep(
      isHost: isHost,
      sessionId: _sessionId,
      messages: ep.incoming.stream,
      send: ep.send,
      done: ep.done,
      clock: clock,
    );

void main() {
  group('pvpMatchSeed', () {
    test('is deterministic, order-sensitive, and 31-bit', () {
      const hostNonce = '0123456789abcdef';
      const guestNonce = 'fedcba9876543210';
      final seed = pvpMatchSeed(hostNonce, guestNonce);
      expect(seed, pvpMatchSeed(hostNonce, guestNonce));
      expect(seed, isNot(pvpMatchSeed(guestNonce, hostNonce)));
      expect(seed, inInclusiveRange(0, 0x7fffffff));
    });
  });

  group('PvpLockstep over a fake transport', () {
    test('input delay: sampled intent is stamped frame+3 and gates stepping',
        () {
      final ep = _FakeEndpoint();
      final engine = _engine();
      final driver = _driverFor(ep, isHost: true)..attach(engine);

      // First pump samples frame 3 and steps only the agreed-silence
      // frames 0..2 (both sides prefilled them).
      final stepped = driver.pump(() => const FighterIntent(FighterIntent.right));
      expect(stepped, 3);
      expect(driver.steppedFrames, 3);
      expect(engine.frame, 3);
      final firstInput = ep.sent.firstWhere((m) => m.type == PvpMessage.input);
      expect(firstInput.data['frame'], 3);
      expect(firstInput.data['bits'], FighterIntent.right);

      // No peer input for frame 3: further pumps sample ahead but the
      // engine does not step.
      driver.pump(() => FighterIntent.none);
      driver.pump(() => FighterIntent.none);
      expect(driver.steppedFrames, 3);
      expect(engine.frame, 3);

      // The peer's frame-3 input arrives: frame 3 steps.
      ep.inject(
        const PvpMessage(PvpMessage.input, _sessionId, {'frame': 3, 'bits': 0}),
      );
      driver.pump(() => FighterIntent.none);
      expect(driver.steppedFrames, 4);
      expect(engine.frame, 4);
    });

    test('history window heals a lost input message', () {
      final ep = _FakeEndpoint();
      final engine = _engine();
      final driver = _driverFor(ep, isHost: true)..attach(engine);
      driver.pump(() => FighterIntent.none); // samples frame 3
      driver.pump(() => FighterIntent.none); // samples frame 4
      expect(driver.steppedFrames, 3);

      // Frame 3's message is lost; frame 4's arrives carrying frame 3 in
      // its history window. Both frames now step.
      ep.inject(
        const PvpMessage(PvpMessage.input, _sessionId, {
          'frame': 4,
          'bits': 0,
          'hist': [
            [3, 0],
          ],
        }),
      );
      driver.pump(() => FighterIntent.none);
      expect(driver.steppedFrames, 5);
    });

    test('stalls after 10 dry pumps, then aborts at the 5 s timeout', () {
      var now = DateTime(2026, 1, 1);
      final ep = _FakeEndpoint();
      final engine = _engine();
      final driver = _driverFor(ep, isHost: false, clock: () => now)
        ..attach(engine);
      String? abortReason;
      driver.onAbort = (reason) => abortReason = reason;

      driver.pump(() => FighterIntent.none); // steps the prefill frames
      expect(driver.steppedFrames, 3);
      for (var i = 0; i < 12; i++) {
        driver.pump(() => FighterIntent.none);
      }
      expect(driver.stalled, isTrue);
      expect(driver.aborted, isFalse);
      expect(engine.frame, 3); // frozen while stalled

      now = now.add(const Duration(seconds: 6));
      driver.pump(() => FighterIntent.none);
      expect(driver.aborted, isTrue);
      expect(driver.abortReason, contains('stopped answering'));
      expect(abortReason, driver.abortReason);
      expect(
        ep.sent.any((m) => m.type == PvpMessage.abort),
        isTrue,
        reason: 'the peer is told the match died',
      );
    });

    test('a peer abort message aborts the match with their reason', () {
      final ep = _FakeEndpoint();
      final driver = _driverFor(ep, isHost: true)..attach(_engine());
      ep.inject(
        const PvpMessage(PvpMessage.abort, _sessionId, {'reason': 'left'}),
      );
      expect(driver.aborted, isTrue);
      expect(driver.abortReason, contains('left'));
    });

    test('socket close aborts the match', () async {
      final ep = _FakeEndpoint();
      final driver = _driverFor(ep, isHost: true)..attach(_engine());
      ep.close();
      await Future<void>.delayed(Duration.zero);
      expect(driver.aborted, isTrue);
      expect(driver.abortReason, contains('left the match'));
    });

    test("'need' asks for a re-send and the match recovers", () {
      final (aEp, bEp) = _pair();
      final a = _driverFor(aEp, isHost: true)..attach(_engine());
      final b = _driverFor(bEp, isHost: false)..attach(_engine());
      // Eat B's inputs for frames 3..6 (the original sends only). One
      // lost input would heal from the next message's history window;
      // four in a row leaves frame 3 beyond the window, so A must ask
      // for a re-send. The re-sends themselves pass.
      final droppedFrames = <int>{};
      bEp.dropWhen = (m) {
        final frame = m.data['frame'];
        if (m.type == PvpMessage.input &&
            frame is int &&
            frame >= 3 &&
            frame <= 6 &&
            !droppedFrames.contains(frame)) {
          droppedFrames.add(frame);
          return true;
        }
        return false;
      };
      for (var i = 0; i < 30 && a.steppedFrames < 6; i++) {
        a.pump(() => FighterIntent.none);
        b.pump(() => FighterIntent.none);
      }
      expect(droppedFrames, {3, 4, 5, 6});
      expect(
        aEp.sent.any((m) => m.type == PvpMessage.need),
        isTrue,
        reason: 'A asked for the missing frame again',
      );
      expect(a.steppedFrames, greaterThanOrEqualTo(6));
      expect(b.steppedFrames, greaterThanOrEqualTo(6));
    });
  });

  group('two endpoints over real sockets', () {
    test(
      'start exchange + 300 lockstep frames end in identical states',
      () async {
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

        // Both nonces are known to both sessions, so the agreed seed is
        // already identical before the start exchange runs.
        expect(hostSession.matchSeed, guestSession.matchSeed);
        expect(hostSession.hostNonce, guestSession.hostNonce);
        expect(hostSession.guestNonce, guestSession.guestNonce);

        final hostStart = pvpExchangeStart(
          session: hostSession,
          myPubkey: hostKey.pubkeyHex,
          mySign: 'aries',
          sign: (bytes) => _sign(hostKey.pair, bytes),
        );
        final guestStart = pvpExchangeStart(
          session: guestSession,
          myPubkey: guestKey.pubkeyHex,
          mySign: 'leo',
          sign: (bytes) => _sign(guestKey.pair, bytes),
        );
        final hostResult = await hostStart;
        final guestResult = await guestStart;
        expect(hostResult.peerSign, 'leo');
        expect(guestResult.peerSign, 'aries');
        expect(hostResult.seed, guestResult.seed);
        expect(hostResult.seed, hostSession.matchSeed);

        final hostEngine = MatchEngine(
          p1: offlineFighter('aries')!,
          p2: offlineFighter('leo')!,
          seed: hostResult.seed,
          mode: 'pvp',
        );
        final guestEngine = MatchEngine(
          p1: offlineFighter('aries')!,
          p2: offlineFighter('leo')!,
          seed: guestResult.seed,
          mode: 'pvp',
        );
        final hostDriver = PvpLockstep.over(hostSession)..attach(hostEngine);
        final guestDriver = PvpLockstep.over(guestSession)
          ..attach(guestEngine);
        addTearDown(hostDriver.dispose);
        addTearDown(guestDriver.dispose);

        // Scripted intents, keyed by each side's own pump count: the
        // host walks in and swings, the guest walks in, blocks, swings.
        var hostPumps = 0;
        FighterIntent hostSampler() {
          final i = hostPumps++;
          if (i < 90) return FighterIntent.none;
          if (i < 150) return const FighterIntent(FighterIntent.right);
          return i % 7 == 0
              ? const FighterIntent(FighterIntent.hp)
              : FighterIntent.none;
        }

        var guestPumps = 0;
        FighterIntent guestSampler() {
          final i = guestPumps++;
          if (i < 90) return FighterIntent.none;
          if (i < 150) return const FighterIntent(FighterIntent.left);
          if (i % 11 == 0) return const FighterIntent(FighterIntent.block);
          return i % 5 == 0
              ? const FighterIntent(FighterIntent.hk)
              : FighterIntent.none;
        }

        for (var i = 0;
            i < 900 &&
                (hostDriver.steppedFrames < 300 ||
                    guestDriver.steppedFrames < 300);
            i++) {
          hostDriver.pump(hostSampler);
          guestDriver.pump(guestSampler);
          await Future<void>.delayed(Duration.zero);
        }
        expect(hostDriver.aborted, isFalse);
        expect(guestDriver.aborted, isFalse);
        expect(hostDriver.steppedFrames, greaterThanOrEqualTo(300));
        expect(guestDriver.steppedFrames, greaterThanOrEqualTo(300));
        expect(hostDriver.steppedFrames, guestDriver.steppedFrames);

        // The determinism proof: identical seed + identical inputs on
        // both sides produce byte-identical engine states.
        expect(hostEngine.stateBytes(), guestEngine.stateBytes());
        expect(hostEngine.p1.x, guestEngine.p1.x);
        expect(hostEngine.p1.hp, guestEngine.p1.hp);
        expect(hostEngine.p2.x, guestEngine.p2.x);
        expect(hostEngine.p2.hp, guestEngine.p2.hp);
        expect(hostEngine.wins, guestEngine.wins);
        expect(hostEngine.round, guestEngine.round);
        // And the scripted inputs really drove the fight: P1 walked in
        // from its start position.
        expect(hostEngine.p1.x, greaterThan(MatchEngine.startX1));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
