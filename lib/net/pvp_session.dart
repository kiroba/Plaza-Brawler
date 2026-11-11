// PvP slice S1 — pairing + transport skeleton (p2p-connectivity-spec §5).
//
// Two phones on the same LAN pair (QR payload, or a 6-digit session code
// plus manual IP entry), connect over a plain WebSocket, and run a signed
// hello/ready handshake. No gameplay here: S2 adds the lockstep loop on top
// of the [PvpSession] this file returns.
//
// Pure Dart: no Flutter / dart:ui imports, so this file is unit-testable in
// the VM (see test/pvp_session_test.dart). Transport is dart:io only.
// Signing is Ed25519; the caller supplies the sign callback (in the app
// that is StargateIdentity.signBytes) and verification uses
// package:cryptography directly, so the handshake logic itself never
// touches secure storage.
//
// Two join paths (spec §3.2 leaves the manual fallback to S1 to decide):
//  - QR / pinned: the guest knows the full [PvpPairingPayload] (session id
//    + host key) from the host's QR code and pins the host key before
//    connecting; a mismatched key or signature aborts.
//  - Code + IP: the guest only knows the 6-digit session code and the
//    host's IP:port. The code is the shared secret — the host only
//    completes the handshake when it matches — and the guest checks the
//    host's challenge signature is self-consistent under the key the host
//    presents. Weaker than pinning (the code is the trust anchor), but it
//    is the working S1 join path until in-app QR scanning lands.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// Protocol version carried in the pairing payload.
const int pvpProtocolVersion = 1;

/// First port the host tries; falls back up the range when it is taken.
/// Deliberately clear of the daemon ports (5000 IPC, 5005 mesh, 9100
/// telemetry). The port actually bound is the one in the pairing payload.
const int pvpDefaultPort = 5077;
const int _pvpPortFallbacks = 10;

/// How long a guest waits for the TCP/WebSocket connect.
const Duration pvpConnectTimeout = Duration(seconds: 10);

/// How long either side waits for the next handshake message.
const Duration pvpHandshakeTimeout = Duration(seconds: 20);

/// How long a host waits for a guest to show up before giving up.
const Duration pvpHostWaitTimeout = Duration(seconds: 120);

/// Signs [bytes] with this phone's Ed25519 key; returns a 128-char hex
/// signature (StargateIdentity.signBytes in the app).
typedef PvpSign = Future<String> Function(List<int> bytes);

/// Something went wrong with pairing or the handshake. [message] is
/// plain words for the lobby screen to show.
class PvpError implements Exception {
  final String message;
  const PvpError(this.message);
  @override
  String toString() => 'PvpError: $message';
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd hex');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

bool _isHex(String s, int length) =>
    s.length == length &&
    s.codeUnits.every(
      (c) =>
          (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66),
    );

bool _isIpv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255 || p != n.toString()) return false;
  }
  return true;
}

/// One decoded-message stream per socket. A WebSocket is a
/// single-subscription stream, so the handshake and the session must share
/// one listener: this converts it once, into a broadcast stream both can
/// use, dropping malformed frames instead of throwing.
Stream<PvpMessage> _incoming(WebSocket socket) => socket
    .map((event) => event is String ? PvpMessage.tryDecode(event) : null)
    .whereType<PvpMessage>()
    .asBroadcastStream();

/// The pairing payload the host shows as a QR code (spec §3.2):
/// `{v:1, host_ip, port, session_id, host_pubkey, nonce}`. The guest pins
/// [hostPubkey] from this payload (out-of-band trust) and verifies the
/// host's signature against it during connect.
class PvpPairingPayload {
  final int version;
  final String hostIp;
  final int port;
  final String sessionId;
  final String hostPubkey;
  final String nonce;

  const PvpPairingPayload({
    required this.version,
    required this.hostIp,
    required this.port,
    required this.sessionId,
    required this.hostPubkey,
    required this.nonce,
  });

  /// The exact string encoded in the host's QR code.
  String toQrString() => jsonEncode({
        'v': version,
        'host_ip': hostIp,
        'port': port,
        'session_id': sessionId,
        'host_pubkey': hostPubkey,
        'nonce': nonce,
      });

  /// Parses a scanned QR string; returns null when anything is missing or
  /// malformed (wrong version, bad IP, short keys, bad port).
  static PvpPairingPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['v'];
      final hostIp = decoded['host_ip'];
      final port = decoded['port'];
      final sessionId = decoded['session_id'];
      final hostPubkey = decoded['host_pubkey'];
      final nonce = decoded['nonce'];
      if (version != pvpProtocolVersion ||
          hostIp is! String ||
          !_isIpv4(hostIp) ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          sessionId is! String ||
          !_isHex(sessionId, 32) ||
          hostPubkey is! String ||
          !_isHex(hostPubkey, 64) ||
          nonce is! String ||
          !_isHex(nonce, 16)) {
        return null;
      }
      return PvpPairingPayload(
        version: version,
        hostIp: hostIp,
        port: port,
        sessionId: sessionId,
        hostPubkey: hostPubkey,
        nonce: nonce,
      );
    } catch (_) {
      return null;
    }
  }

  /// The 6-digit session code for a session id: first 3 bytes of
  /// sha256(sessionId) as a number, mod 1,000,000. Deterministic, so the
  /// host can check a guest-entered code without any lookup.
  static String codeForSession(String sessionId) {
    final digest = sha256.convert(_unhex(sessionId)).bytes;
    final n = (digest[0] << 16) | (digest[1] << 8) | digest[2];
    return (n % 1000000).toString().padLeft(6, '0');
  }
}

/// One framed message on the PvP socket: JSON text, one object per
/// WebSocket frame. `t` is the type, `s` the session id, the rest is
/// per-type data. The session id is empty in a code-path guest's first
/// hello (it does not know the id yet); every later message carries the
/// real 32-hex id.
class PvpMessage {
  static const String hello = 'hello';
  static const String challenge = 'challenge';
  static const String ready = 'ready';
  static const String abort = 'abort';
  static const Set<String> types = {hello, challenge, ready, abort};

  final String type;
  final String sessionId;
  final Map<String, dynamic> data;

  const PvpMessage(this.type, this.sessionId, [this.data = const {}]);

  String encode() => jsonEncode({'t': type, 's': sessionId, ...data});

  /// Decodes one frame; returns null when it is not a well-formed PvP
  /// message (bad JSON, unknown type, malformed session id).
  static PvpMessage? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['t'];
      final sessionId = decoded['s'];
      if (type is! String ||
          !types.contains(type) ||
          sessionId is! String ||
          !(sessionId.isEmpty || _isHex(sessionId, 32))) {
        return null;
      }
      final data = Map<String, dynamic>.from(decoded)
        ..remove('t')
        ..remove('s');
      return PvpMessage(type, sessionId, data);
    } catch (_) {
      return null;
    }
  }
}

/// The exact bytes each side signs. The prefixes keep a PvP signature from
/// ever being mistaken for another protocol's signature.
List<int> pvpChallengeBytes(
  String sessionId,
  String hostNonce,
  String guestNonce,
) =>
    utf8.encode('pvp-challenge|$sessionId|$hostNonce|$guestNonce');

List<int> pvpReadyBytes(
  String sessionId,
  String hostNonce,
  String guestPubkey,
) =>
    utf8.encode('pvp-ready|$sessionId|$hostNonce|$guestPubkey');

/// Verifies an Ed25519 signature over [message] against [pubkeyHex].
/// Returns false for malformed keys/signatures instead of throwing.
Future<bool> pvpVerify(
  List<int> message,
  String signatureHex,
  String pubkeyHex,
) async {
  try {
    final pub = _unhex(pubkeyHex);
    final sig = _unhex(signatureHex);
    if (pub.length != 32 || sig.length != 64) return false;
    return await Ed25519().verify(
      message,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

/// First non-loopback, non-link-local IPv4 address on this phone (the LAN
/// address the other phone can reach), or null when there is none — e.g.
/// Wi-Fi off. LAN interfaces only; never 0.0.0.0.
Future<InternetAddress?> pvpLanIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  for (final nic in interfaces) {
    for (final addr in nic.addresses) {
      if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
        return addr;
      }
    }
  }
  return null;
}

/// An established PvP session: the handshake is done, both sides know each
/// other's public key. S2 drives gameplay over [messages]; S1 only uses
/// [sendAbort]/[close]/[done].
class PvpSession {
  final WebSocket _socket;
  final Stream<PvpMessage> messages;
  final String peerPubkey;
  final bool isHost;
  final String sessionId;

  PvpSession(this._socket, {
    required this.messages,
    required this.peerPubkey,
    required this.isHost,
    required this.sessionId,
  });

  /// Completes when the socket closes for any reason (abort, peer left,
  /// network drop).
  Future<void> get done => _socket.done;

  Future<void> sendAbort(String reason) async {
    try {
      _socket.add(
        PvpMessage(PvpMessage.abort, sessionId, {'reason': reason}).encode(),
      );
      await _socket.flush();
    } catch (_) {}
  }

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}

/// The host side: listens on the LAN, shows the pairing payload, and runs
/// the handshake for the first guest that connects.
class PvpHost {
  final HttpServer _server;
  final String pubkeyHex;
  final PvpSign _sign;
  final PvpPairingPayload payload;

  PvpHost._(this._server, {
    required this.pubkeyHex,
    required PvpSign sign,
    required this.payload,
  }) : _sign = sign;

  /// The 6-digit code the guest types (derived from the session id).
  String get sessionCode => PvpPairingPayload.codeForSession(payload.sessionId);

  /// Creates the listener and the pairing payload. [bindAddress] is only
  /// for tests (production always binds the LAN address from
  /// [pvpLanIpv4]). Throws [PvpError] when there is no LAN address or no
  /// port in the fallback range could be opened.
  static Future<PvpHost> create({
    required String pubkeyHex,
    required PvpSign sign,
    InternetAddress? bindAddress,
  }) async {
    final ip = bindAddress ?? await pvpLanIpv4();
    if (ip == null) {
      throw const PvpError(
        'No LAN Wi-Fi found — connect both phones to the same Wi-Fi first.',
      );
    }
    HttpServer? server;
    var boundPort = pvpDefaultPort;
    for (var p = pvpDefaultPort; p < pvpDefaultPort + _pvpPortFallbacks; p++) {
      try {
        server = await HttpServer.bind(ip, p);
        boundPort = p;
        break;
      } on SocketException {
        continue;
      }
    }
    if (server == null) {
      throw const PvpError('Could not open a PvP port on this phone.');
    }
    final rnd = Random.secure();
    final sessionId = _hex(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final nonce = _hex(List<int>.generate(8, (_) => rnd.nextInt(256)));
    return PvpHost._(
      server,
      pubkeyHex: pubkeyHex,
      sign: sign,
      payload: PvpPairingPayload(
        version: pvpProtocolVersion,
        hostIp: ip.address,
        port: boundPort,
        sessionId: sessionId,
        hostPubkey: pubkeyHex,
        nonce: nonce,
      ),
    );
  }

  /// Waits for one guest and runs the host half of the handshake:
  /// hello (checks session id + code) -> challenge (host signs) -> ready
  /// (verifies the guest's signature). Throws [PvpError] on timeout,
  /// wrong code, bad signature, or a peer abort.
  Future<PvpSession> waitForGuest({
    Duration timeout = pvpHostWaitTimeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    try {
      await for (final request in _server.timeout(timeout)) {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        try {
          return await _handshake(socket, deadline);
        } on PvpError {
          await _closeSocket(socket);
          rethrow;
        } catch (_) {
          await _closeSocket(socket);
          throw const PvpError('The guest connection broke mid-handshake.');
        }
      }
    } on TimeoutException {
      throw const PvpError('No guest joined in time.');
    }
    throw const PvpError('No guest joined in time.');
  }

  Future<PvpSession> _handshake(WebSocket socket, DateTime deadline) async {
    final incoming = _incoming(socket);
    final hello = await _nextMessage(incoming, deadline);
    if (hello.type != PvpMessage.hello) {
      throw const PvpError('The guest did not say hello properly.');
    }
    // A QR guest states the session id; a code guest sends an empty one
    // (it does not know it yet) and is identified by the code alone.
    if (hello.sessionId.isNotEmpty &&
        hello.sessionId != payload.sessionId) {
      throw const PvpError('The guest joined the wrong session.');
    }
    final guestPubkey = hello.data['guest_pubkey'];
    final guestNonce = hello.data['guest_nonce'];
    final code = hello.data['code'];
    if (guestPubkey is! String ||
        !_isHex(guestPubkey, 64) ||
        guestNonce is! String ||
        !_isHex(guestNonce, 16) ||
        code != sessionCode) {
      throw const PvpError('The guest code or key did not check out.');
    }
    final hostNonce = payload.nonce;
    final signature = await _sign(
      pvpChallengeBytes(payload.sessionId, hostNonce, guestNonce),
    );
    socket.add(
      PvpMessage(PvpMessage.challenge, payload.sessionId, {
        'host_pubkey': pubkeyHex,
        'host_nonce': hostNonce,
        'signature': signature,
      }).encode(),
    );
    final ready = await _nextMessage(incoming, deadline);
    if (ready.type != PvpMessage.ready ||
        ready.sessionId != payload.sessionId) {
      throw const PvpError('The guest never confirmed ready.');
    }
    final readySig = ready.data['signature'];
    if (readySig is! String ||
        !await pvpVerify(
          pvpReadyBytes(payload.sessionId, hostNonce, guestPubkey),
          readySig,
          guestPubkey,
        )) {
      throw const PvpError("The guest's signature did not check out.");
    }
    socket.add(PvpMessage(PvpMessage.ready, payload.sessionId).encode());
    return PvpSession(
      socket,
      messages: incoming,
      peerPubkey: guestPubkey,
      isHost: true,
      sessionId: payload.sessionId,
    );
  }

  /// Next message from the peer, or throws [PvpError] on timeout or on an
  /// abort message from the peer.
  Future<PvpMessage> _nextMessage(
    Stream<PvpMessage> incoming,
    DateTime deadline,
  ) async {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      throw const PvpError('The handshake timed out.');
    }
    try {
      final message = await incoming.first.timeout(remaining);
      if (message.type == PvpMessage.abort) {
        throw PvpError(
          'The other phone left (${message.data['reason'] ?? 'no reason'}).',
        );
      }
      return message;
    } on TimeoutException {
      throw const PvpError('The handshake timed out.');
    }
  }

  Future<void> _closeSocket(WebSocket socket) async {
    try {
      await socket.close();
    } catch (_) {}
  }

  /// Stops listening. Does not close an established session (the caller
  /// owns that socket).
  Future<void> close() async {
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}

/// The guest side: connects to a host and runs the guest half of the
/// handshake. Two entry points — [connect] for a scanned QR payload
/// (host key pinned before connecting) and [connectManual] for a typed
/// session code + host IP/port (the code is the shared secret; the host's
/// challenge signature is checked for self-consistency under the key the
/// host presents).
class PvpGuest {
  static Future<PvpSession> connect({
    required PvpPairingPayload payload,
    required String code,
    required String pubkeyHex,
    required PvpSign sign,
    Duration timeout = pvpConnectTimeout,
  }) =>
      _connect(
        hostIp: payload.hostIp,
        port: payload.port,
        code: code,
        pubkeyHex: pubkeyHex,
        sign: sign,
        timeout: timeout,
        pinned: payload,
      );

  static Future<PvpSession> connectManual({
    required String hostIp,
    required int port,
    required String code,
    required String pubkeyHex,
    required PvpSign sign,
    Duration timeout = pvpConnectTimeout,
  }) =>
      _connect(
        hostIp: hostIp,
        port: port,
        code: code,
        pubkeyHex: pubkeyHex,
        sign: sign,
        timeout: timeout,
        pinned: null,
      );

  static Future<PvpSession> _connect({
    required String hostIp,
    required int port,
    required String code,
    required String pubkeyHex,
    required PvpSign sign,
    required Duration timeout,
    required PvpPairingPayload? pinned,
  }) async {
    final rnd = Random.secure();
    final guestNonce = _hex(List<int>.generate(8, (_) => rnd.nextInt(256)));
    late final WebSocket socket;
    try {
      socket = await WebSocket.connect('ws://$hostIp:$port').timeout(timeout);
    } on TimeoutException {
      throw const PvpError('Could not reach the host phone in time.');
    } catch (_) {
      throw const PvpError(
        'Could not reach the host phone. Same Wi-Fi, and the code + IP as shown?',
      );
    }
    final incoming = _incoming(socket);
    try {
      // A pinned guest states the session id it expects; a manual guest
      // sends an empty one and learns it from the challenge.
      socket.add(
        PvpMessage(PvpMessage.hello, pinned?.sessionId ?? '', {
          'guest_pubkey': pubkeyHex,
          'guest_nonce': guestNonce,
          'code': code,
        }).encode(),
      );
      final challenge = await _nextMessage(incoming);
      if (challenge.type != PvpMessage.challenge) {
        throw const PvpError('The host answered wrong. Aborted.');
      }
      final sessionId = challenge.sessionId;
      if (pinned != null && sessionId != pinned.sessionId) {
        throw const PvpError('The host answered for the wrong session.');
      }
      final hostPubkey = challenge.data['host_pubkey'];
      final hostNonce = challenge.data['host_nonce'];
      final signature = challenge.data['signature'];
      // Pinned: the key must be the one from the QR. Manual: the signature
      // must verify under whatever key the host presents.
      if (hostPubkey is! String ||
          !_isHex(hostPubkey, 64) ||
          (pinned != null && hostPubkey != pinned.hostPubkey) ||
          hostNonce is! String ||
          !_isHex(hostNonce, 16) ||
          signature is! String ||
          !await pvpVerify(
            pvpChallengeBytes(sessionId, hostNonce, guestNonce),
            signature,
            hostPubkey,
          )) {
        throw const PvpError(
          "The host's key or signature did not match the pairing. Aborted.",
        );
      }
      final readySig = await sign(
        pvpReadyBytes(sessionId, hostNonce, pubkeyHex),
      );
      socket.add(
        PvpMessage(PvpMessage.ready, sessionId, {
          'guest_pubkey': pubkeyHex,
          'signature': readySig,
        }).encode(),
      );
      final ready = await _nextMessage(incoming);
      if (ready.type != PvpMessage.ready || ready.sessionId != sessionId) {
        throw const PvpError('The host never confirmed ready. Aborted.');
      }
      return PvpSession(
        socket,
        messages: incoming,
        peerPubkey: hostPubkey,
        isHost: false,
        sessionId: sessionId,
      );
    } on PvpError {
      await _closeSocket(socket);
      rethrow;
    } on TimeoutException {
      await _closeSocket(socket);
      throw const PvpError('The handshake timed out.');
    } catch (_) {
      await _closeSocket(socket);
      throw const PvpError('The host connection broke mid-handshake.');
    }
  }

  static Future<PvpMessage> _nextMessage(Stream<PvpMessage> incoming) async {
    final message = await incoming.first.timeout(pvpHandshakeTimeout);
    if (message.type == PvpMessage.abort) {
      throw PvpError(
        'The host turned us away (${message.data['reason'] ?? 'no reason'}).',
      );
    }
    return message;
  }

  static Future<void> _closeSocket(WebSocket socket) async {
    try {
      await socket.close();
    } catch (_) {}
  }
}
