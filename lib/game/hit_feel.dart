// Hit-stop and KO slow-mo for the fight screen. Pure Dart, presentation only: MatchEngine is untouched and
// stays deterministic. The screen asks [shouldTick] once per 60 Hz display step and only calls
// engine.tick() when it says yes, so a freeze or slow-mo only delays engine frames; it never changes them
// (the same intents in the same order give the same match, see test/hit_feel_test.dart).
import '../audio/sfx.dart';
import 'match_engine.dart';

class HitFeel {
  /// The sounds for one engine frame's fx, at most one of each (Flare Rush and traded hits can land twice
  /// in one frame). A KO plays only the KO sound. Otherwise a landed heavy, special or guard break plays
  /// the heavy hit (instead of the light one), any other landed hit the light hit, and a blocked hit the
  /// block thud; a landed hit and a block in the same frame play both. Same split as the hit-stop below.
  static List<SfxKind> soundsFor(Iterable<HitFx> fx) {
    if (fx.isEmpty) return const [];
    if (fx.any((f) => f.ko)) return const [SfxKind.ko];
    final landed = fx.where((f) => !f.blocked || f.guardBreak);
    final out = <SfxKind>[];
    if (landed.any((f) => f.heavy || f.special || f.guardBreak)) {
      out.add(SfxKind.heavy);
    } else if (landed.isNotEmpty) {
      out.add(SfxKind.hit);
    }
    if (fx.any((f) => f.blocked && !f.guardBreak)) out.add(SfxKind.block);
    return out;
  }

  /// Display steps frozen on a landed light hit.
  static const int lightStop = 4;

  /// Display steps frozen on a blocked hit (a small "clack", shorter than a landed hit).
  static const int blockStop = 2;

  /// Display steps frozen on a landed heavy, special (Flare Rush etc.) or guard break.
  static const int heavyStop = 8;

  /// Display steps frozen on the KO hit, before the slow-mo starts.
  static const int koStop = 12;

  /// Display steps of KO slow-mo (~1 s at 60 Hz).
  static const int koSlowSteps = 60;

  /// During slow-mo the engine runs one frame every [koSlowEvery] display steps (half speed).
  static const int koSlowEvery = 2;

  int _freeze = 0;
  int _slow = 0;
  int _slowPhase = 0;

  /// Display steps of freeze left.
  int get freezeLeft => _freeze;

  /// Display steps of KO slow-mo left.
  int get slowLeft => _slow;

  /// True while a KO is being shown in freeze/slow-mo: the screen holds the "K.O." result banner back
  /// until this is false.
  bool get holdingKo => _koActive && (_freeze > 0 || _slow > 0);
  bool _koActive = false;

  /// Feed the engine's fx from the frame that just ran. A new hit never shortens a freeze already running
  /// (max, not sum), so Flare Rush's 3 quick hits feel heavy without stacking into a long stall.
  void onFx(Iterable<HitFx> fx) {
    for (final f in fx) {
      if (f.ko) {
        _koActive = true;
        if (_freeze < koStop) _freeze = koStop;
        _slow = koSlowSteps;
        _slowPhase = 0;
        continue;
      }
      final stop = f.blocked && !f.guardBreak
          ? blockStop
          : (f.heavy || f.special || f.guardBreak ? heavyStop : lightStop);
      if (_freeze < stop) _freeze = stop;
    }
  }

  /// One display step: true when the engine should run a frame now.
  bool shouldTick() {
    if (_freeze > 0) {
      _freeze--;
      return false;
    }
    if (_slow > 0) {
      _slow--;
      _slowPhase++;
      final run = _slowPhase % koSlowEvery == 0;
      if (_slow == 0) _koActive = false;
      return run;
    }
    _koActive = false;
    return true;
  }

  /// Clears everything (new match / attract pair).
  void reset() {
    _freeze = 0;
    _slow = 0;
    _slowPhase = 0;
    _koActive = false;
  }
}
