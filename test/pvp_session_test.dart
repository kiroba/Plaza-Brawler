// PvP slice S1 — pairing + handshake tests (pure Dart, runs in the VM).
// The end-to-end tests bind real loopback sockets: one host, one guest,
// no phones needed.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:plaza_brawler/net/pvp_session.dart';
import 'package:test/test.dart';

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

const _sessionId = '0123456789abcdef0123456789abcdef';
const _pubkey =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _nonce = '0123456789abcdef';

PvpPairingPayload _payload() => const PvpPairingPayload(
      version: 1,
      hostIp: '192.168.1.5',
      port: 5077,
      sessionId: _sessionId,
      hostPubkey: _pubkey,
      nonce: _nonce,
    );

void main() {
  group('PvpPairingPayload', () {
    test('QR string round-trips', () {
      final parsed = PvpPairingPayload.tryParse(_payload().toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.hostIp, '192.168.1.5');
      expect(parsed.port, 5077);
      expect(parsed.sessionId, _sessionId);
      expect(parsed.hostPubkey, _pubkey);
      expect(parsed.nonce, _nonce);
    });

    test('rejects malformed payloads', () {
      expect(PvpPairingPayload.tryParse('not json'), isNull);
      expect(PvpPairingPayload.tryParse('{"v":2}'), isNull);
      expect(
        PvpPairingPayload.tryParse(
          _payload().toQrString().replaceAll('192.168.1.5', '999.1.1.1'),
        ),
        isNull,
      );
      expect(
        PvpPairingPayload.tryParse(
          _payload().toQrString().replaceAll(_pubkey, 'abcd'),
        ),
        isNull,
      );
      expect(
        PvpPairingPayload.tryParse(
          _payload().toQrString().replaceAll('"port":5077', '"port":70000'),
        ),
        isNull,
      );
    });

    test('session code is 6 digits, deterministic, session-specific', () {
      final code = PvpPairingPayload.codeForSession(_sessionId);
      expect(code.length, 6);
      expect(int.tryParse(code), isNotNull);
      expect(PvpPairingPayload.codeForSession(_sessionId), code);
      expect(
        PvpPairingPayload.codeForSession(
          'fedcba9876543210fedcba9876543210',
        ),
        isNot(code),
      );
    });
  });

  group('PvpMessage', () {
    test('encode/decode round-trips every type', () {
      for (final type in PvpMessage.types) {
        final msg = PvpMessage(type, _sessionId, {'k': 'v'});
        final decoded = PvpMessage.tryDecode(msg.encode());
        expect(decoded, isNotNull);
        expect(decoded!.type, type);
        expect(decoded.sessionId, _sessionId);
        expect(decoded.data['k'], 'v');
      }
    });

    test('rejects unknown types, bad session ids, bad JSON', () {
      expect(PvpMessage.tryDecode('{"t":"nope","s":"$_sessionId"}'), isNull);
      expect(PvpMessage.tryDecode('{"t":"hello","s":"short"}'), isNull);
      expect(PvpMessage.tryDecode('{bad json'), isNull);
      expect(PvpMessage.tryDecode('[]'), isNull);
    });
  });

  group('pvpVerify', () {
    test('accepts a real signature, rejects wrong key and garbage', () async {
      final key = await _newKey();
      final other = await _newKey();
      final message = [1, 2, 3, 4];
      final sig = await _sign(key.pair, message);
      expect(await pvpVerify(message, sig, key.pubkeyHex), isTrue);
      expect(await pvpVerify(message, sig, other.pubkeyHex), isFalse);
      expect(await pvpVerify(message, 'zz', key.pubkeyHex), isFalse);
      expect(await pvpVerify(message, sig, 'zz'), isFalse);
      expect(await pvpVerify([9, 9], sig, key.pubkeyHex), isFalse);
    });
  });

  group('handshake over loopback sockets', () {
    late String hostPub;
    late String guestPub;
    late PvpSign hostSign;
    late PvpSign guestSign;

    setUp(() async {
      final hostKey = await _newKey();
      final guestKey = await _newKey();
      hostPub = hostKey.pubkeyHex;
      guestPub = guestKey.pubkeyHex;
      hostSign = (bytes) => _sign(hostKey.pair, bytes);
      guestSign = (bytes) => _sign(guestKey.pair, bytes);
    });

    Future<PvpHost> _host() => PvpHost.create(
          pubkeyHex: hostPub,
          sign: hostSign,
          bindAddress: InternetAddress.loopbackIPv4,
        );

    test('pinned QR connect reaches ready on both sides', () async {
      final host = await _host();
      addTearDown(host.close);
      final hostFuture = host.waitForGuest(
        timeout: const Duration(seconds: 10),
      );
      final guestSession = await PvpGuest.connect(
        payload: host.payload,
        code: host.sessionCode,
        pubkeyHex: guestPub,
        sign: guestSign,
      );
      final hostSession = await hostFuture;
      addTearDown(hostSession.close);
      addTearDown(guestSession.close);
      expect(hostSession.peerPubkey, guestPub);
      expect(guestSession.peerPubkey, hostPub);
      expect(hostSession.isHost, isTrue);
      expect(guestSession.isHost, isFalse);
      expect(hostSession.sessionId, host.payload.sessionId);
      expect(guestSession.sessionId, host.payload.sessionId);
    });

    test('manual code connect reaches ready', () async {
      final host = await _host();
      addTearDown(host.close);
      final hostFuture = host.waitForGuest(
        timeout: const Duration(seconds: 10),
      );
      final guestSession = await PvpGuest.connectManual(
        hostIp: host.payload.hostIp,
        port: host.payload.port,
        code: host.sessionCode,
        pubkeyHex: guestPub,
        sign: guestSign,
      );
      final hostSession = await hostFuture;
      addTearDown(hostSession.close);
      addTearDown(guestSession.close);
      expect(hostSession.peerPubkey, guestPub);
      expect(guestSession.peerPubkey, hostPub);
    });

    test('wrong session code aborts', () async {
      final host = await _host();
      addTearDown(host.close);
      final hostFuture = host.waitForGuest(
        timeout: const Duration(seconds: 10),
      );
      await expectLater(
        PvpGuest.connect(
          payload: host.payload,
          code: '000000',
          pubkeyHex: guestPub,
          sign: guestSign,
        ),
        throwsA(isA<PvpError>()),
      );
      await expectLater(hostFuture, throwsA(isA<PvpError>()));
    });

    test('tampered pinned host key aborts', () async {
      final host = await _host();
      addTearDown(host.close);
      final hostFuture = host.waitForGuest(
        timeout: const Duration(seconds: 10),
      );
      final tampered = PvpPairingPayload(
        version: host.payload.version,
        hostIp: host.payload.hostIp,
        port: host.payload.port,
        sessionId: host.payload.sessionId,
        hostPubkey: guestPub,
        nonce: host.payload.nonce,
      );
      await expectLater(
        PvpGuest.connect(
          payload: tampered,
          code: host.sessionCode,
          pubkeyHex: guestPub,
          sign: guestSign,
        ),
        throwsA(isA<PvpError>()),
      );
      await expectLater(hostFuture, throwsA(isA<PvpError>()));
    });

    test('guest abort after ready reaches the host cleanly', () async {
      final host = await _host();
      addTearDown(host.close);
      final hostFuture = host.waitForGuest(
        timeout: const Duration(seconds: 10),
      );
      final guestSession = await PvpGuest.connect(
        payload: host.payload,
        code: host.sessionCode,
        pubkeyHex: guestPub,
        sign: guestSign,
      );
      final hostSession = await hostFuture;
      addTearDown(hostSession.close);
      addTearDown(guestSession.close);
      final abortSeen = hostSession.messages.firstWhere(
        (m) => m.type == PvpMessage.abort,
      );
      await guestSession.sendAbort('test-leave');
      final abort = await abortSeen.timeout(const Duration(seconds: 5));
      expect(abort.data['reason'], 'test-leave');
      await guestSession.close();
      await hostSession.done.timeout(const Duration(seconds: 5));
    });
  });
}
