// PvP slice S3 — the dual-signed result (p2p-connectivity-spec §5).
//
// When a lockstep match ends cleanly (no desync — the hash checkpoints
// in pvp_lockstep.dart guard that), both phones build the SAME result
// payload from data they already hold identically: the session id, the
// agreed seed, both public keys, both fighter signs, and the engine
// summary (winner, round results, final state hash). Each side signs
// the payload with its own identity key and the signatures are swapped
// over the session; the completed envelope — payload + BOTH signatures —
// is what gets stored on the phone and, only when the player turned
// match sharing on, POSTed to Omni Node (MatchShare.sharePvpMatch).
//
// A payload that differs between the phones (e.g. a divergence the
// checkpoints didn't catch, visible in the final state hash) makes the
// peer's signature fail verification against the local payload, the
// exchange throws, and nothing is recorded — the same no-result outcome
// as a desync.
//
// Pure Dart: no Flutter / dart:ui imports, unit-testable in the VM.
import 'dart:async';
import 'dart:convert';

import 'pvp_session.dart';

/// Builds the S3 result payload in its canonical form: this literal key
/// order IS the canonical encoding — Dart maps keep insertion order and
/// jsonEncode emits it unchanged, so both phones produce byte-identical
/// JSON (and sign byte-identical bytes, see pvpResultBytes) as long as
/// the values agree. [summary] is MatchEngine.summary() at match end.
Map<String, dynamic> pvpMatchPayload({
  required String sessionId,
  required int seed,
  required String hostPubkey,
  required String guestPubkey,
  required String hostSign,
  required String guestSign,
  required Map<String, dynamic> summary,
}) {
  return {
    'v': 1,
    'session_id': sessionId,
    'seed': seed,
    'host_pubkey': hostPubkey,
    'guest_pubkey': guestPubkey,
    'p1_sign': hostSign,
    'p2_sign': guestSign,
    'winner': summary['winner'],
    'wins': summary['wins'],
    'rounds': summary['rounds'],
    'duration_ms': summary['duration_ms'],
    'final_state_hash': summary['final_state_hash'],
  };
}

/// A completed PvP result: the shared [payload] plus each player's
/// Ed25519 signature over pvpResultBytes(payload), keyed by role (the
/// host is P1, the guest is P2). This is the `pvp_match` envelope the
/// spec names — the unit that gets stored and (opt-in) shared.
class PvpMatchEnvelope {
  final Map<String, dynamic> payload;
  final String hostSignature;
  final String guestSignature;

  const PvpMatchEnvelope({
    required this.payload,
    required this.hostSignature,
    required this.guestSignature,
  });

  /// The stored / shared form: one JSON object, signatures beside the
  /// payload they cover.
  Map<String, dynamic> toJson() => {
        'type': 'pvp_match',
        'payload': payload,
        'signatures': {'host': hostSignature, 'guest': guestSignature},
      };

  /// True when BOTH signatures verify against the public keys named in
  /// the payload itself. A tampered payload or a signature made over a
  /// different payload fails.
  Future<bool> verify() async {
    final hostPubkey = payload['host_pubkey'];
    final guestPubkey = payload['guest_pubkey'];
    if (hostPubkey is! String || guestPubkey is! String) return false;
    final bytes = pvpResultBytes(payload);
    return await pvpVerify(bytes, hostSignature, hostPubkey) &&
        await pvpVerify(bytes, guestSignature, guestPubkey);
  }
}

/// Swaps result signatures over [session] until the peer's is verified
/// against [payload], then returns the completed envelope. Sends our own
/// signature first and re-sends it every 500 ms until the peer's arrives
/// (the session stream is broadcast, so a result sent before we
/// subscribed would otherwise be lost — the same pattern as the S2 start
/// exchange). Throws [PvpError] on timeout, on a peer abort, on a closed
/// socket, or when the peer's signature does not verify against our
/// payload — in every failure case nothing is recorded or shared.
Future<PvpMatchEnvelope> pvpExchangeResult({
  required PvpSession session,
  required Map<String, dynamic> payload,
  required PvpSign sign,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final mySignature = await sign(pvpResultBytes(payload));
  final resultMessage = PvpMessage(PvpMessage.result, session.sessionId, {
    'signature': mySignature,
  });

  final completer = Completer<PvpMatchEnvelope>();
  var settled = false;
  void settle(void Function() action) {
    if (settled) return;
    settled = true;
    action();
  }

  PvpMatchEnvelope complete(String peerSignature) => session.isHost
      ? PvpMatchEnvelope(
          payload: payload,
          hostSignature: mySignature,
          guestSignature: peerSignature,
        )
      : PvpMatchEnvelope(
          payload: payload,
          hostSignature: peerSignature,
          guestSignature: mySignature,
        );

  final subscription = session.messages.listen((message) {
    if (message.sessionId != session.sessionId) return;
    if (message.type == PvpMessage.abort) {
      settle(
        () => completer.completeError(
          const PvpError(
            'The match result did not check out — nothing was recorded.',
          ),
        ),
      );
      return;
    }
    if (message.type != PvpMessage.result || completer.isCompleted) return;
    final sig = message.data['signature'];
    if (sig is! String) return;
    pvpVerify(pvpResultBytes(payload), sig, session.peerPubkey).then((ok) {
      if (!ok) {
        settle(
          () => completer.completeError(
            const PvpError(
              'The match result did not check out — nothing was recorded.',
            ),
          ),
        );
        return;
      }
      settle(() => completer.complete(complete(sig)));
    });
  });
  final doneSubscription = session.done.asStream().listen(
    (_) {
      settle(
        () => completer.completeError(
          const PvpError(
            'The other phone left before the result was confirmed — nothing was recorded.',
          ),
        ),
      );
    },
    onError: (_) {},
  );

  session.send(resultMessage);
  final resend = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (!settled) session.send(resultMessage);
  });
  try {
    return await completer.future.timeout(
      timeout,
      onTimeout: () => throw const PvpError(
        'The match result was never confirmed — nothing was recorded.',
      ),
    );
  } finally {
    settled = true;
    resend.cancel();
    await subscription.cancel();
    await doneSubscription.cancel();
  }
}

/// The canonical JSON of a result payload (what jsonEncode produces from
/// pvpMatchPayload's fixed key order). Exposed for tests and debugging.
String pvpMatchCanonical(Map<String, dynamic> payload) =>
    jsonEncode(payload);
