// Demo-day (kiosk) mode logic (spec 4.7). Pure Dart (package:crypto only), driven by an injectable clock.
// Real: salted sha256 PIN (4 digits, never stored in clear), idle timers (attract loop after 30 s on the title,
// auto-return after a run, fight pause/abandon), the hidden exit (5 taps on the corner within 3 s, then the PIN)
// with a wrong-PIN cooldown, and a fresh session per player. Not here: wakelock, immersive mode, PIN storage
// (flutter_secure_storage) and the attract-loop screen itself; the widgets call into this class.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Where the app is, as far as the kiosk timers care.
enum KioskScreen { title, attract, fight, runEnd, other }

/// What the widget layer should do now.
enum KioskAction { none, startAttract, pauseFight, returnToTitle }

/// PIN rules and hashing. The stored form is `<salt hex>$<sha256 hex of "salt:pin">`.
class KioskPin {
  KioskPin._();

  static final RegExp _fourDigits = RegExp(r'^[0-9]{4}$');

  static bool isValid(String pin) => _fourDigits.hasMatch(pin);

  static String _digest(String saltHex, String pin) =>
      sha256.convert(utf8.encode('$saltHex:$pin')).toString();

  /// A new stored hash for [pin] (random 16-byte salt unless [saltHex] is given, for tests).
  /// Throws ArgumentError for anything but exactly 4 digits.
  static String hash(String pin, {String? saltHex, Random? random}) {
    if (!isValid(pin)) throw ArgumentError('PIN must be exactly 4 digits');
    final rng = random ?? Random.secure();
    final salt =
        saltHex ??
        List.generate(
          16,
          (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '$salt\$${_digest(salt, pin)}';
  }

  /// True when [pin] matches [stored]. Constant-time compare; false for any malformed input.
  static bool verify(String pin, String? stored) {
    if (stored == null || !isValid(pin)) return false;
    final i = stored.indexOf(r'$');
    if (i <= 0 || i == stored.length - 1) return false;
    final want = stored.substring(i + 1);
    final got = _digest(stored.substring(0, i), pin);
    if (want.length != got.length) return false;
    var diff = 0;
    for (var k = 0; k < got.length; k++) {
      diff |= want.codeUnitAt(k) ^ got.codeUnitAt(k);
    }
    return diff == 0;
  }
}

/// One player's session at the table: a fresh run seed and nothing carried over from the last player.
class KioskSession {
  final int id;
  final int runSeed;
  final int startedMs;

  const KioskSession({
    required this.id,
    required this.runSeed,
    required this.startedMs,
  });
}

class KioskController {
  // Timers (ms). Attract after 30 s idle on the title (Keith's Nov 3 brief; spec v2 said 20 s).
  static const attractIdleMs = 30000;
  static const runEndReturnMs = 10000;
  static const fightPauseMs = 45000;
  static const fightAbandonMs = fightPauseMs + 15000;

  // Hidden exit: 5 taps on the corner within 3 s, then the PIN.
  static const exitTaps = 5;
  static const exitTapWindowMs = 3000;

  // Wrong-PIN cooldown so strangers can't brute-force 10,000 PINs at the table.
  static const maxPinTries = 5;
  static const pinCooldownMs = 30000;

  final int Function() _now;
  final Random _rng;

  bool enabled;
  String? pinHash;

  int _lastActivity;
  final List<int> _cornerTaps = [];
  bool _exitPromptOpen = false;
  int _wrongPins = 0;
  int _lockedUntil = 0;
  late KioskSession _session;

  /// Called after every [resetSession] (clear selected sign, how-to-play seen flag, input state...).
  final List<void Function(KioskSession)> onSessionReset = [];

  KioskController({
    this.enabled = false,
    this.pinHash,
    int Function()? nowMs,
    Random? random,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _rng = random ?? Random(),
       _lastActivity = 0 {
    _lastActivity = _now();
    _session = _newSession(1);
  }

  KioskSession get session => _session;
  bool get exitPromptOpen => _exitPromptOpen;
  int get idleMs => _now() - _lastActivity;

  /// Ms until PINs are accepted again (0 when not locked out).
  int get pinLockedMs => max(0, _lockedUntil - _now());

  KioskSession _newSession(int id) =>
      KioskSession(id: id, runSeed: _rng.nextInt(1 << 31), startedMs: _now());

  /// Turns kiosk mode on with a new PIN (Settings -> Demo-day mode). Returns false for a bad PIN.
  bool enable(String pin) {
    if (!KioskPin.isValid(pin)) return false;
    pinHash = KioskPin.hash(pin);
    enabled = true;
    _wrongPins = 0;
    _lockedUntil = 0;
    noteActivity();
    return true;
  }

  /// Any touch or key. Resets the idle timer.
  void noteActivity() => _lastActivity = _now();

  /// What to do on [screen] right now. Call it from a periodic timer (e.g. every 500 ms).
  KioskAction evaluate(KioskScreen screen) {
    if (!enabled || _exitPromptOpen) return KioskAction.none;
    final idle = idleMs;
    switch (screen) {
      case KioskScreen.title:
        return idle >= attractIdleMs
            ? KioskAction.startAttract
            : KioskAction.none;
      case KioskScreen.runEnd:
        return idle >= runEndReturnMs
            ? KioskAction.returnToTitle
            : KioskAction.none;
      case KioskScreen.fight:
        if (idle >= fightAbandonMs) return KioskAction.returnToTitle;
        return idle >= fightPauseMs ? KioskAction.pauseFight : KioskAction.none;
      case KioskScreen.attract:
      case KioskScreen.other:
        return KioskAction.none;
    }
  }

  /// A tap on the hidden corner. Returns true when this tap completes 5 within 3 s: show the PIN prompt.
  bool cornerTap() {
    if (!enabled) return false;
    final t = _now();
    _cornerTaps
      ..add(t)
      ..removeWhere((x) => t - x > exitTapWindowMs);
    if (_cornerTaps.length >= exitTaps) {
      _cornerTaps.clear();
      _exitPromptOpen = true;
      return true;
    }
    return false;
  }

  /// The PIN typed into the exit prompt. True: kiosk mode is off. False: wrong PIN, locked out or no prompt.
  bool submitExitPin(String pin) {
    if (!enabled || !_exitPromptOpen || pinLockedMs > 0) return false;
    if (KioskPin.verify(pin, pinHash)) {
      enabled = false;
      _exitPromptOpen = false;
      _wrongPins = 0;
      noteActivity();
      return true;
    }
    _wrongPins++;
    if (_wrongPins >= maxPinTries) {
      _wrongPins = 0;
      _lockedUntil = _now() + pinCooldownMs;
      _exitPromptOpen = false;
    }
    return false;
  }

  /// Checks the PIN for a PIN-gated action (e.g. "Reset demo data") without leaving kiosk mode.
  bool checkPin(String pin) =>
      pinLockedMs == 0 && KioskPin.verify(pin, pinHash);

  void cancelExitPrompt() {
    _exitPromptOpen = false;
    noteActivity();
  }

  /// Between players: new session id and run seed, idle timer and hidden-exit taps cleared, listeners told.
  KioskSession resetSession() {
    _cornerTaps.clear();
    _exitPromptOpen = false;
    noteActivity();
    _session = _newSession(_session.id + 1);
    for (final f in List.of(onSessionReset)) {
      f(_session);
    }
    return _session;
  }
}
