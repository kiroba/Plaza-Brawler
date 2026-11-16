// Gamepad bridge (desktop D3): the only place the `gamepads` plugin is touched. It forwards
// normalized plugin events into the pure-Dart GamepadInput (lib/game/gamepad_input.dart), using
// the plugin's standard-model names (GamepadButton/GamepadAxis `.name`), which are exactly the
// names GamepadInput maps.
//
// Windows only: the subscription is created solely on Windows, so on Android the plugin is
// never listened to, its Android activity forwarding is never needed, and the Android build
// behaves exactly as before. Any pad works for P1; with several pads connected their inputs
// merge into the one GamepadInput (v0 is a one-controller slice).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:gamepads/gamepads.dart';

import '../game/gamepad_input.dart';

class GamepadBridge {
  final GamepadInput input;
  StreamSubscription<NormalizedGamepadEvent>? _sub;

  GamepadBridge(this.input);

  void start() {
    if (!Platform.isWindows) return;
    _sub ??= Gamepads.normalizedEvents.listen(
      (event) {
        final button = event.button;
        if (button != null) {
          if (event.value != 0) {
            input.buttonDown(button.name);
          } else {
            input.buttonUp(button.name);
          }
          return;
        }
        final axis = event.axis;
        if (axis != null) input.axis(axis.name, event.value);
      },
      // No pad connected / plugin unavailable: stay silent. Keyboard and touch still drive P1.
      onError: (_) {},
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
