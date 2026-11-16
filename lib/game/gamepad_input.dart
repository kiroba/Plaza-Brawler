// Gamepad input (desktop D3): one more InputSource beside Touch/Keyboard, so MatchEngine is
// untouched. Pure Dart like the rest of lib/game/: the plugin bridge (lib/input/gamepad_bridge.dart)
// feeds it normalized button/axis names from the `gamepads` package's standard model
// (a/b/x/y, dpad*, leftStickX/Y), and this file owns the mapping to FighterIntent bits.
//
// Mapping v0 (existing seven intents only; no new moves, no 8-way pad):
//   dpadLeft / stick left   -> left      dpadRight / stick right -> right
//   dpadUp / stick up       -> up (jump)
//   a -> light   b -> heavy   x -> block   y -> special
// Stick Y follows the gamepads normalized convention (up = +1). The exact face-button layout is
// confirmed against a real controller in the D4 playtest reps; remapping is a one-line change
// in [buttonMap].
import 'input.dart';
import 'match_engine.dart';

class GamepadInput implements InputSource {
  /// How far the left stick must be pushed before it counts as a direction.
  static const double stickThreshold = 0.5;

  /// Normalized gamepads button name -> intent bit. Buttons not listed here (bumpers, triggers,
  /// start/back/home, dpadDown) map to nothing: v0 has no intent for them.
  static const Map<String, int> buttonMap = {
    'dpadLeft': FighterIntent.left,
    'dpadRight': FighterIntent.right,
    'dpadUp': FighterIntent.up,
    'a': FighterIntent.light,
    'b': FighterIntent.heavy,
    'x': FighterIntent.block,
    'y': FighterIntent.special,
  };

  final Set<String> _down = {};
  int _latched = 0;
  double _stickX = 0;
  double _stickY = 0;

  /// Set when a mapped button is pressed, for the kiosk idle timer.
  void Function()? onActivity;

  /// Returns true when [name] is one of ours. Same latch discipline as Touch/Keyboard: a quick
  /// tap between two ticks is latched so it is never lost.
  bool buttonDown(String name) {
    final f = buttonMap[name];
    if (f == null) return false;
    _down.add(name);
    _latched |= f;
    onActivity?.call();
    return true;
  }

  bool buttonUp(String name) {
    if (!buttonMap.containsKey(name)) return false;
    _down.remove(name);
    return true;
  }

  /// Left stick only; every other axis is ignored (the right stick has no intent in v0).
  void axis(String name, double value) {
    if (name == 'leftStickX') {
      _stickX = value;
    } else if (name == 'leftStickY') {
      _stickY = value;
    }
  }

  void releaseAll() {
    _down.clear();
    _latched = 0;
    _stickX = 0;
    _stickY = 0;
  }

  int get _held {
    var b = 0;
    for (final name in _down) {
      b |= buttonMap[name] ?? 0;
    }
    if (_stickX <= -stickThreshold) b |= FighterIntent.left;
    if (_stickX >= stickThreshold) b |= FighterIntent.right;
    if (_stickY >= stickThreshold) b |= FighterIntent.up;
    return b;
  }

  @override
  FighterIntent poll(MatchSnapshot s) {
    final bits = _held | _latched;
    _latched = 0;
    return FighterIntent(bits);
  }
}
