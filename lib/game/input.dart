// Input abstraction (spec 4.2): one FighterIntent per tick from any InputSource. Pure Dart.
// Real: TouchInput (on-screen buttons), KeyboardInput (desktop A/D/W + J/K/L/I), CpuInput (arcade AI).
// Stubbed: RemoteInput for player vs player over the mesh is a LATER PR (see the PvP hook below).
import 'cpu_brain.dart';
import 'match_engine.dart';

/// What a fighter wants to do this tick, as bits (cheap to send over a socket for lockstep later).
class FighterIntent {
  static const left = 1;
  static const right = 2;
  static const up = 4; // jump
  static const light = 8;
  static const heavy = 16;
  static const block = 32;
  static const special = 64;

  final int bits;
  const FighterIntent(this.bits);

  static const none = FighterIntent(0);

  bool has(int flag) => bits & flag != 0;

  /// -1 left, 0 none, 1 right.
  int get dir {
    final l = has(left), r = has(right);
    if (l == r) return 0;
    return l ? -1 : 1;
  }

  @override
  bool operator ==(Object other) =>
      other is FighterIntent && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() => 'FighterIntent(0x${bits.toRadixString(16)})';
}

/// Anything that can drive a fighter: a person on this phone, a keyboard, the CPU, later a peer.
abstract class InputSource {
  /// Called exactly once per engine tick.
  FighterIntent poll(MatchSnapshot s);
}

/// On-screen buttons. Buttons call [press]/[release]; a quick tap between two ticks is latched so it
/// is never lost.
class TouchInput implements InputSource {
  int _held = 0;
  int _latched = 0;

  /// Set when any button changes, for the kiosk idle timer.
  void Function()? onActivity;

  void press(int flag) {
    _held |= flag;
    _latched |= flag;
    onActivity?.call();
  }

  void release(int flag) {
    _held &= ~flag;
    onActivity?.call();
  }

  void releaseAll() {
    _held = 0;
    _latched = 0;
  }

  @override
  FighterIntent poll(MatchSnapshot s) {
    final bits = _held | _latched;
    _latched = 0;
    return FighterIntent(bits);
  }
}

/// Desktop keyboard: A/D or arrows to move, W/up to jump, J light, K heavy, L block, I or Space special.
/// Keys are plain lowercase labels so this stays Flutter-free; the fight screen maps key events.
class KeyboardInput implements InputSource {
  final Set<String> _down = {};
  int _latched = 0;

  static const Map<String, int> keymap = {
    'a': FighterIntent.left,
    'arrow left': FighterIntent.left,
    'd': FighterIntent.right,
    'arrow right': FighterIntent.right,
    'w': FighterIntent.up,
    'arrow up': FighterIntent.up,
    'j': FighterIntent.light,
    'k': FighterIntent.heavy,
    'l': FighterIntent.block,
    'i': FighterIntent.special,
    ' ': FighterIntent.special,
    'space': FighterIntent.special,
  };

  /// Returns true when the key is one of ours.
  bool keyDown(String label) {
    final f = keymap[label.toLowerCase()];
    if (f == null) return false;
    _down.add(label.toLowerCase());
    _latched |= f;
    return true;
  }

  bool keyUp(String label) {
    final f = keymap[label.toLowerCase()];
    if (f == null) return false;
    _down.remove(label.toLowerCase());
    return true;
  }

  int get _held {
    var b = 0;
    for (final k in _down) {
      b |= keymap[k] ?? 0;
    }
    return b;
  }

  @override
  FighterIntent poll(MatchSnapshot s) {
    final bits = _held | _latched;
    _latched = 0;
    return FighterIntent(bits);
  }
}

/// Touch and keyboard together (a phone with a Bluetooth keyboard, or desktop with a mouse).
class MergedInput implements InputSource {
  final List<InputSource> sources;
  MergedInput(this.sources);

  @override
  FighterIntent poll(MatchSnapshot s) {
    var b = 0;
    for (final src in sources) {
      b |= src.poll(s).bits;
    }
    return FighterIntent(b);
  }
}

/// The arcade AI. [side] is 0 for P1, 1 for P2.
class CpuInput implements InputSource {
  final CpuBrain brain;
  final int side;
  CpuInput(this.brain, {this.side = 1});

  @override
  FighterIntent poll(MatchSnapshot s) => brain.decide(s, side);
}

// PvP hook: `class RemoteInput implements InputSource` goes here in the multiplayer PR (spec 11).
// It will return the peer's intent bits for the frame from the lockstep buffer (lib/game/lockstep.dart),
// so MatchEngine stays unchanged: player vs player is just a second InputSource.
