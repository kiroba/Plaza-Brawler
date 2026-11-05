// App-wide state for Plaza Brawler (spec 6): replaces the old GameData statics.
// Real: the sign the player picked (saved on this phone, since the LPE profile has no sign), the how-to-play
// flag, the "Share my match results" toggle, high-score and feedback repos, and Demo-day (kiosk) mode:
// PIN hash in flutter_secure_storage, a 500 ms timer that runs KioskController.evaluate() for the screen on
// top, wakelock (wakelock_plus) and immersive fullscreen while kiosk mode is on. Sound effects on/off (saved
// here, played by lib/audio/sfx.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio/sfx.dart';
import 'audio/sfx_audioplayers.dart';
import 'game/feedback.dart';
import 'game/high_scores.dart';
import 'game/kiosk.dart';
import 'net/match_share.dart';
import 'net/omni_node.dart';

/// The app's one Navigator (kiosk "return to title" pops it from outside any widget).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Route names. The kiosk timers read which kind of screen is on top from these.
class Routes {
  Routes._();
  static const title = 'title';
  static const attract = 'attract';
  static const fight = 'fight';
  static const runEnd = 'run_end';
  static const gameOver = 'game_over';
  static const select = 'select';
  static const versus = 'versus';
  static const howToPlay = 'how_to_play';
  static const highScores = 'high_scores';
  static const initials = 'initials';
  static const feedback = 'feedback';
  static const dialog = 'dialog';
  static const settings = 'settings';

  /// Plain dark page under every Arcade / Quick Fight step (screens/brawler_ui.dart FlowBackdrop).
  static const flow = 'flow';

  static KioskScreen kioskScreenFor(String? name) {
    switch (name) {
      case title:
        return KioskScreen.title;
      case attract:
        return KioskScreen.attract;
      case fight:
        return KioskScreen.fight;
      case runEnd:
      case gameOver:
        return KioskScreen.runEnd;
      case select:
      case versus:
      case howToPlay:
      case highScores:
      case initials:
      case feedback:
      case dialog:
      case flow:
        return KioskScreen.menu;
      default:
        return KioskScreen.other;
    }
  }
}

/// Keeps [AppState.currentRoute] equal to the name of the route on top.
class KioskRouteObserver extends NavigatorObserver {
  final List<String?> _stack = [];

  void _top() => appState.currentRoute = _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route.settings.name);
    _top();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty) _stack.removeLast();
    _top();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final i = _stack.lastIndexOf(route.settings.name);
    if (i >= 0) _stack.removeAt(i);
    _top();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null
        ? -1
        : _stack.lastIndexOf(oldRoute.settings.name);
    if (i >= 0) {
      _stack[i] = newRoute?.settings.name;
    } else {
      _stack.add(newRoute?.settings.name);
    }
    _top();
  }
}

class AppState extends ChangeNotifier {
  static const appVersion = '5.5.0';

  static const FlutterSecureStorage _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kSign = 'plaza_brawler_sign_v1';
  static const _kHowTo = 'plaza_brawler_howto_seen_v1';
  // v2: v1 could come back ON from an older build or an Android backup restore while the screen said "Off by
  // default". v1 is deleted on load, so every phone starts with sharing off.
  static const _kShare = 'plaza_brawler_share_matches_v2';
  static const _kShareOld = 'plaza_brawler_share_matches_v1';
  static const _kMuted = 'plaza_brawler_sfx_muted_v1';
  static const _kKioskOn = 'plaza_brawler_kiosk_on_v1';
  static const _kKioskPin = 'plaza_brawler_kiosk_pin_v1';

  final KioskController kiosk = KioskController();
  final HighScoreRepo highScores = HighScoreRepo();
  final FeedbackRepo feedback = FeedbackRepo();
  late final MatchShare matchShare = MatchShare(
    saveLocal: (summary) =>
        omniNode.dispatchEvent('FIGHTER_MATCH_END', summary),
    token: () => omniNode.token,
    appVersion: appVersion,
  );
  final KioskRouteObserver routeObserver = KioskRouteObserver();

  /// The sign picked on this phone (null until the first pick). Not used in kiosk mode: every player picks.
  String? chosenSign;
  bool _howToSeen = false;
  bool _howToSeenThisSession = false;

  /// Quick Fights finished since launch (feedback is asked after every third).
  int quickFights = 0;

  /// Name of the route on top (see [Routes]).
  String? currentRoute;

  /// Set by the title screen (start the attract loop) and the fight screen (pause).
  VoidCallback? onStartAttract;
  VoidCallback? onPauseFight;

  Timer? _kioskTimer;

  AppState() {
    kiosk.onSessionReset.add((_) => _howToSeenThisSession = false);
  }

  bool get kioskOn => kiosk.enabled;
  bool get shareEnabled => matchShare.shareEnabled;

  /// True once Omni Node on this phone lists "games_match" in node-health (daemon 8.28.0+). Until then the
  /// "Share my match results" switch is shown off and disabled ("turns on when Omni Node supports it").
  bool get nodeAcceptsMatchShares => matchShare.nodeSupportsMatches == true;

  /// Re-reads node-health's features (boot, Settings refresh). Never throws.
  Future<void> probeMatchSharing() async {
    await matchShare.probe();
    notifyListeners();
  }

  bool get soundOn => !sfx.muted;

  /// True when the how-to-play card should come before the next fight (first fight per install, or per
  /// player in kiosk mode).
  bool get needsHowToPlay => kioskOn ? !_howToSeenThisSession : !_howToSeen;

  Future<String?> _read(String k) async {
    try {
      return await _store.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String k, String? v) async {
    try {
      if (v == null) {
        await _store.delete(key: k);
      } else {
        await _store.write(key: k, value: v);
      }
    } catch (_) {}
  }

  /// Reads everything saved on this phone. Never throws.
  Future<void> load() async {
    chosenSign = await _read(_kSign);
    _howToSeen = await _read(_kHowTo) == '1';
    // Off unless the player turned it on (v2 key; the node's support is checked separately).
    matchShare.shareEnabled = await _read(_kShare) == '1';
    await _write(_kShareOld, null);
    sfx.muted = await _read(_kMuted) == '1';
    // Not awaited: a slow or broken audio service must never hold up boot. Sfx never throws.
    unawaited(sfx.init(AudioplayersBackend.new));
    final pin = await _read(_kKioskPin);
    if (await _read(_kKioskOn) == '1' && pin != null && pin.isNotEmpty) {
      kiosk.pinHash = pin;
      kiosk.enabled = true;
      kiosk.noteActivity();
    }
    await _applyKioskSystem();
    notifyListeners();
  }

  Future<void> setChosenSign(String sign) async {
    if (kioskOn) return; // a stranger's pick isn't saved for the next one
    chosenSign = sign;
    await _write(_kSign, sign);
    notifyListeners();
  }

  Future<void> markHowToPlaySeen() async {
    _howToSeenThisSession = true;
    if (!_howToSeen) {
      _howToSeen = true;
      await _write(_kHowTo, '1');
    }
  }

  Future<void> setShareEnabled(bool on) async {
    if (on && !nodeAcceptsMatchShares)
      return; // can't turn on until the node supports it
    matchShare.shareEnabled = on;
    await _write(_kShare, on ? '1' : '0');
    notifyListeners();
  }

  /// Settings "Sound effects" switch.
  Future<void> setSoundOn(bool on) async {
    sfx.muted = !on;
    await _write(_kMuted, on ? null : '1');
    notifyListeners();
  }

  /// Settings -> Demo-day mode on, with a new 4-digit PIN. False for a bad PIN.
  Future<bool> enableKiosk(String pin) async {
    if (!kiosk.enable(pin)) return false;
    await _write(_kKioskPin, kiosk.pinHash);
    await _write(_kKioskOn, '1');
    kiosk.resetSession();
    await _applyKioskSystem();
    notifyListeners();
    return true;
  }

  /// Demo-day mode off and the PIN cleared (Settings, or the hidden exit after the right PIN).
  Future<void> disableKiosk() async {
    kiosk.disable();
    await _write(_kKioskOn, null);
    await _write(_kKioskPin, null);
    await _applyKioskSystem();
    notifyListeners();
  }

  /// The PIN typed into the hidden-exit prompt. True when kiosk mode is now off.
  Future<bool> submitExitPin(String pin) async {
    if (!kiosk.submitExitPin(pin)) {
      notifyListeners();
      return false;
    }
    await disableKiosk();
    return true;
  }

  Future<void> _applyKioskSystem() async {
    try {
      if (kioskOn) {
        await WakelockPlus.enable();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await WakelockPlus.disable();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  /// Starts the ~500 ms kiosk loop (idempotent).
  void startKioskTimer() {
    _kioskTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _evaluate(),
    );
  }

  void _evaluate() {
    final action = kiosk.evaluate(Routes.kioskScreenFor(currentRoute));
    switch (action) {
      case KioskAction.none:
        break;
      case KioskAction.startAttract:
        onStartAttract?.call();
        break;
      case KioskAction.pauseFight:
        onPauseFight?.call();
        break;
      case KioskAction.returnToTitle:
        returnToTitle();
        break;
    }
  }

  /// Back to the title with a fresh player session.
  void returnToTitle() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    kiosk.resetSession();
    notifyListeners();
  }

  /// Tell listeners (title chips) that node status changed.
  void refresh() => notifyListeners();

  /// Settings / hidden-exit "Reset demo data": clears high scores and feedback on this phone.
  Future<void> resetDemoData() async {
    await highScores.clear();
    await feedback.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _kioskTimer?.cancel();
    super.dispose();
  }
}

final appState = AppState();
