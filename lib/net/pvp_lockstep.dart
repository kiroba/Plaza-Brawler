// PvP slice S2 — lockstep versus play (p2p-connectivity-spec §3.4, §5).
//
// On top of an established S1 [PvpSession]:
//  1. [pvpExchangeStart] swaps signed start messages: each side names the
//     fighter sign it picked, signed over the session + both nonces, so a
//     start cannot be replayed into another pairing. Both sides then hold
//     both signs and the agreed seed (PvpSession.matchSeed =
//     sha256(host_nonce || guest_nonce), spec §3.4).
//  2. [PvpLockstep] drives one MatchEngine in lockstep: every display
//     tick it samples the local intent, stamps it frame+3 (the fixed
//     3-frame input delay), sends it, and steps the engine only when both
//     sides' intents for a frame exist. Host intent is always P1, guest
//     intent always P2, on both phones.
//
// Stall behaviour (spec §3.4): if the peer's next input is missing for
// more than 10 ticks the match freezes and reports stalled (the fight
// screen shows "Waiting for opponent…"); after 5 s without progress the
// match aborts with no result. A dropped input message heals two ways:
// every input message repeats the previous 3 frames (history window),
// and a side that is missing a frame asks for a re-send ('need').
//
// S3 integrity (spec §5): every [hashInterval] stepped frames each side
// hashes its engine state (MatchEngine.stateHash) and swaps the hash
// with the peer. A mismatch means the two engines have diverged — a
// DESYNC: the match aborts on both sides with [desyncReason], and no
// result is recorded or shared. The result envelope itself (dual-signed,
// stored, opt-in shared) is pvp_result.dart, run by the lobby at a clean
// match end; the driver never posts anything to the node.
//
// Pure Dart: no Flutter / dart:ui imports, unit-testable in the VM.
import 'dart:async';

import '../game/input.dart';
import '../game/match_engine.dart';
import '../npc/zodiac_offline.dart';
import 'pvp_session.dart';

/// The outcome of the start exchange: the peer's chosen fighter sign and
/// the agreed match seed both sides derived from the nonces.
class PvpStartResult {
  final String peerSign;
  final int seed;
  const PvpStartResult({required this.peerSign, required this.seed});
}

/// Exchanges signed start messages over [session] until the peer's start
/// is verified, then returns what the peer picked. Sends our own start
/// first and re-sends it every 500 ms until the peer's arrives (the
/// session stream is broadcast, so a start sent before we subscribed
/// would otherwise be lost). Throws [PvpError] on timeout, on a peer
/// abort, on a bad signature, or when either sign is not a known fighter.
Future<PvpStartResult> pvpExchangeStart({
  required PvpSession session,
  required String myPubkey,
  required String mySign,
  required PvpSign sign,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final mine = mySign.trim().toLowerCase();
  if (offlineFighter(mine) == null) {
    throw PvpError('Your fighter pick ($mySign) is not a known sign.');
  }
  final signature = await sign(
    pvpStartBytes(
      session.sessionId,
      session.hostNonce,
      session.guestNonce,
      myPubkey,
      mine,
    ),
  );
  final startMessage = PvpMessage(PvpMessage.start, session.sessionId, {
    'sign': mine,
    'pubkey': myPubkey,
    'signature': signature,
  });

  final completer = Completer<PvpStartResult>();
  var settled = false;
  void settle(void Function() action) {
    if (settled) return;
    settled = true;
    action();
  }

  final subscription = session.messages.listen((message) {
    if (message.sessionId != session.sessionId) return;
    if (message.type == PvpMessage.abort) {
      settle(
        () => completer.completeError(
          PvpError(
            'The other phone left (${message.data['reason'] ?? 'no reason'}).',
          ),
        ),
      );
      return;
    }
    if (message.type != PvpMessage.start || completer.isCompleted) return;
    final peerSign = message.data['sign'];
    final pubkey = message.data['pubkey'];
    final sig = message.data['signature'];
    if (peerSign is! String || pubkey != session.peerPubkey || sig is! String) {
      return;
    }
    final normalized = peerSign.trim().toLowerCase();
    if (offlineFighter(normalized) == null) {
      settle(
        () => completer.completeError(
          const PvpError('The other phone picked an unknown fighter.'),
        ),
      );
      return;
    }
    pvpVerify(
      pvpStartBytes(
        session.sessionId,
        session.hostNonce,
        session.guestNonce,
        session.peerPubkey,
        normalized,
      ),
      sig,
      session.peerPubkey,
    ).then((ok) {
      if (!ok) {
        settle(
          () => completer.completeError(
            const PvpError("The other phone's start did not check out."),
          ),
        );
        return;
      }
      settle(
        () => completer.complete(
          PvpStartResult(peerSign: normalized, seed: session.matchSeed),
        ),
      );
    });
  });
  final doneSubscription = session.done.asStream().listen(
    (_) {
      settle(
        () => completer.completeError(
          const PvpError('The other phone left before the match started.'),
        ),
      );
    },
    onError: (_) {},
  );

  session.send(startMessage);
  final resend = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (!settled) session.send(startMessage);
  });
  try {
    return await completer.future.timeout(
      timeout,
      onTimeout: () => throw const PvpError(
        'The other phone never picked a fighter — match cancelled.',
      ),
    );
  } finally {
    settled = true;
    resend.cancel();
    await subscription.cancel();
    await doneSubscription.cancel();
  }
}

/// Where a lockstep match stands. [stalled] is recoverable (the engine is
/// frozen, waiting on the peer); [aborted] and [finished] are terminal.
enum PvpMatchState { running, stalled, finished, aborted }

/// Drives one [MatchEngine] in lockstep with a peer doing the same.
/// The fight screen calls [pump] once per 60 Hz display step; everything
/// else (message handling, stall timing) is internal.
class PvpLockstep {
  /// Fixed input delay in frames (spec §3.4): an intent sampled now is
  /// stamped for frame+3, so both sides have time to receive it.
  static const int inputDelay = 3;

  /// Ticks without engine progress before the match reports stalled.
  static const int stallAfterPumps = 10;

  /// Ticks without progress before we ask the peer to re-send ('need').
  static const int needAfterPumps = 3;

  /// No progress for this long aborts the match with no result.
  static const Duration stallTimeout = Duration(seconds: 5);

  /// Catch-up cap: engine steps per pump after a stall breaks.
  static const int maxStepsPerPump = 10;

  /// How many past frames each input message repeats (loss healing).
  static const int historyWindow = 3;

  /// Cap on inputs re-sent per 'need' request.
  static const int resendWindow = 30;

  /// S3: stepped frames between state-hash checkpoints (spec §5).
  static const int hashInterval = 60;

  /// The exact words both phones surface when a checkpoint disagrees:
  /// the match is dropped and nothing is recorded or shared.
  static const String desyncReason = 'Match desynced — no result recorded.';

  final bool isHost;
  final String sessionId;
  final Stream<PvpMessage> _messages;
  final void Function(PvpMessage message) _send;
  final DateTime Function() _clock;

  MatchEngine? _engine;
  late final StreamSubscription<PvpMessage> _subscription;
  bool _disposed = false;

  PvpMatchState _state = PvpMatchState.running;
  String? _abortReason;
  bool _desynced = false;

  /// S3 checkpoints: my engine's state hash per checkpoint frame, and
  /// the peer's hashes that arrived before I reached their frame.
  final Map<int, String> _myHashes = {};
  final Map<int, String> _peerHashes = {};

  /// Called once when the match aborts (stall timeout, peer abort, socket
  /// closed). The fight screen uses it to leave back to the lobby.
  void Function(String reason)? onAbort;

  final Map<int, int> _local = {};
  final Map<int, int> _remote = {};
  int _nextSample = inputDelay;
  int _stepped = 0;
  int _pumpsWithoutProgress = 0;
  DateTime _lastProgress;

  PvpLockstep({
    required this.isHost,
    required this.sessionId,
    required Stream<PvpMessage> messages,
    required void Function(PvpMessage message) send,
    required Future<void> done,
    DateTime Function()? clock,
  })  : _messages = messages,
        _send = send,
        _clock = clock ?? DateTime.now,
        _lastProgress = (clock ?? DateTime.now)() {
    // Frames [0, inputDelay) are agreed silence on both sides: neither
    // side samples them, both engines idle through the intro equally.
    for (var f = 0; f < inputDelay; f++) {
      _local[f] = 0;
      _remote[f] = 0;
    }
    _subscription = _messages.listen(_onMessage);
    done.then(
      (_) {
        if (!_disposed) {
          _abort('The other phone left the match.', notifyPeer: false);
        }
      },
      onError: (_) {},
    );
  }

  /// A driver over an established S1 session.
  factory PvpLockstep.over(PvpSession session, {DateTime Function()? clock}) =>
      PvpLockstep(
        isHost: session.isHost,
        sessionId: session.sessionId,
        messages: session.messages,
        send: session.send,
        done: session.done,
        clock: clock,
      );

  PvpMatchState get state => _state;
  bool get stalled => _state == PvpMatchState.stalled;
  bool get aborted => _state == PvpMatchState.aborted;
  bool get finished => _state == PvpMatchState.finished;
  String? get abortReason => _abortReason;

  /// True when the match died as an S3 desync (a state-hash checkpoint
  /// disagreed, here or on the peer). A desynced match is never stored
  /// or shared; the lobby checks this before the result exchange.
  bool get desynced => _desynced;

  /// Engine frames stepped so far (== the next frame waiting for inputs).
  int get steppedFrames => _stepped;

  /// Binds the engine the fight screen built. Call before the first pump.
  void attach(MatchEngine engine) {
    _engine = engine;
    _lastProgress = _clock();
  }

  /// One 60 Hz tick: sample + send the local intent, then step the
  /// engine as far as both sides' inputs allow. Returns frames stepped.
  int pump(FighterIntent Function() sampleLocal) {
    if (_disposed || _state == PvpMatchState.aborted || _state == PvpMatchState.finished) {
      return 0;
    }
    final engine = _engine;
    if (engine == null) return 0;
    if (engine.isOver) {
      _state = PvpMatchState.finished;
      return 0;
    }

    final frame = _nextSample++;
    final bits = sampleLocal().bits & 0x7f;
    _local[frame] = bits;
    _sendInput(frame);

    var steps = 0;
    while (steps < maxStepsPerPump) {
      final local = _local[_stepped];
      final remote = _remote[_stepped];
      if (local == null || remote == null) break;
      if (isHost) {
        engine.tickWith(FighterIntent(local), FighterIntent(remote));
      } else {
        engine.tickWith(FighterIntent(remote), FighterIntent(local));
      }
      _stepped++;
      steps++;
      if (_stepped % hashInterval == 0) _checkpoint(engine);
      if (_state == PvpMatchState.aborted) break; // desynced mid-burst
    }

    final now = _clock();
    if (steps > 0) {
      _lastProgress = now;
      _pumpsWithoutProgress = 0;
      if (_state == PvpMatchState.stalled) _state = PvpMatchState.running;
    } else {
      _pumpsWithoutProgress++;
      if (_pumpsWithoutProgress == needAfterPumps ||
          (_pumpsWithoutProgress > needAfterPumps &&
              _pumpsWithoutProgress % 30 == 0)) {
        _send(PvpMessage(PvpMessage.need, sessionId, {'frame': _stepped}));
      }
      if (_pumpsWithoutProgress > stallAfterPumps) {
        _state = PvpMatchState.stalled;
        if (now.difference(_lastProgress) >= stallTimeout) {
          _abort(
            'The other phone stopped answering — the match ended with no result.',
            notifyPeer: true,
          );
        }
      }
    }
    if (_state != PvpMatchState.aborted && engine.isOver) {
      _state = PvpMatchState.finished;
    }
    return steps;
  }

  /// S3 checkpoint: the engine has just stepped to a checkpoint frame.
  /// Hash its state, send the hash to the peer, and compare against the
  /// peer's hash for this frame when both are in hand — whichever side
  /// gets the second hash does the comparing, so a divergence is caught
  /// by at least one side, which then tells the other (abort 'desync').
  void _checkpoint(MatchEngine engine) {
    final hash = engine.stateHash();
    _myHashes[_stepped] = hash;
    _send(
      PvpMessage(PvpMessage.hash, sessionId, {
        'frame': _stepped,
        'hash': hash,
      }),
    );
    final peerHash = _peerHashes[_stepped];
    if (peerHash != null && peerHash != hash) _desync(notifyPeer: true);
  }

  /// The two engines have diverged: kill the match on both sides with
  /// no result. Runs even from the finished state — until the result
  /// exchange completes, a late checkpoint can still veto the match.
  void _desync({required bool notifyPeer}) {
    _desynced = true;
    if (_state == PvpMatchState.aborted) return;
    _state = PvpMatchState.aborted;
    _abortReason = desyncReason;
    if (notifyPeer) {
      _send(PvpMessage(PvpMessage.abort, sessionId, {'reason': 'desync'}));
    }
    onAbort?.call(desyncReason);
  }

  void _sendInput(int frame) {
    final history = <List<int>>[
      for (var f = frame - 1; f >= frame - historyWindow && f >= inputDelay; f--)
        [f, _local[f]!],
    ];
    _send(
      PvpMessage(PvpMessage.input, sessionId, {
        'frame': frame,
        'bits': _local[frame],
        'hist': history,
      }),
    );
  }

  void _onMessage(PvpMessage message) {
    if (_disposed || message.sessionId != sessionId) return;
    switch (message.type) {
      case PvpMessage.input:
        _recordRemote(message.data['frame'], message.data['bits']);
        final hist = message.data['hist'];
        if (hist is List) {
          for (final entry in hist) {
            if (entry is List && entry.length == 2) {
              _recordRemote(entry[0], entry[1]);
            }
          }
        }
      case PvpMessage.need:
        final from = message.data['frame'];
        if (from is int) {
          final end = from + resendWindow < _nextSample
              ? from + resendWindow
              : _nextSample;
          for (var f = from; f < end; f++) {
            if (_local.containsKey(f)) _sendInput(f);
          }
        }
      case PvpMessage.hash:
        final frame = message.data['frame'];
        final hash = message.data['hash'];
        if (frame is int && hash is String) {
          final mine = _myHashes[frame];
          if (mine != null) {
            if (mine != hash) _desync(notifyPeer: true);
          } else {
            // The peer is ahead of us: compare when we step that frame.
            _peerHashes[frame] = hash;
          }
        }
      case PvpMessage.abort:
        if (message.data['reason'] == 'desync') {
          _desync(notifyPeer: false);
        } else {
          _abort(
            'The other phone left the match (${message.data['reason'] ?? 'no reason'}).',
            notifyPeer: false,
          );
        }
    }
  }

  void _recordRemote(Object? frame, Object? bits) {
    if (frame is! int || bits is! int) return;
    if (frame < inputDelay || bits < 0 || bits > 0x7f) return;
    // First copy wins: a conflicting re-send is a desync (S3's problem);
    // stepping on the first-seen value keeps this side deterministic.
    _remote.putIfAbsent(frame, () => bits);
  }

  void _abort(String reason, {required bool notifyPeer}) {
    if (_state == PvpMatchState.aborted || _state == PvpMatchState.finished) {
      return;
    }
    _state = PvpMatchState.aborted;
    _abortReason = reason;
    if (notifyPeer) {
      _send(PvpMessage(PvpMessage.abort, sessionId, {'reason': 'stalled'}));
    }
    onAbort?.call(reason);
  }

  /// Tells the peer we are leaving mid-match (best effort), so their side
  /// aborts at once instead of waiting out the stall timeout.
  void leave() {
    if (_state == PvpMatchState.running || _state == PvpMatchState.stalled) {
      _send(PvpMessage(PvpMessage.abort, sessionId, {'reason': 'left'}));
      _state = PvpMatchState.aborted;
      _abortReason = 'You left the match.';
    }
  }

  /// Detaches from the session streams. Does not close the socket — the
  /// lobby owns the session.
  Future<void> dispose() async {
    _disposed = true;
    await _subscription.cancel();
  }
}
