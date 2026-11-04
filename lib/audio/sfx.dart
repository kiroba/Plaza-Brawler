// Sound effects: light hit, heavy hit, block, KO, menu select. Pure Dart: the playing is done by an [SfxBackend] (the app
// uses AudioplayersBackend in sfx_audioplayers.dart). Real: mute (Settings, saved on this phone by
// AppState), and sound can never crash the game: every backend call is guarded, a backend that fails to
// start is switched off for the rest of the session, and play() never throws or waits.
import 'dart:async';

/// [hit] is a landed light hit; [heavy] a landed heavy, special (Flare Rush etc.) or guard break.
enum SfxKind { hit, heavy, block, ko, select }

/// What actually plays the sounds. Any method may throw; [Sfx] catches everything.
abstract class SfxBackend {
  /// Prepare [kind] (asset path from [Sfx.assetFor]).
  Future<void> load(SfxKind kind, String asset);

  /// Start [kind] from the beginning (cutting off the same sound if it is still playing).
  Future<void> play(SfxKind kind);
}

class Sfx {
  /// The asset each sound plays (relative to assets/, as audioplayers' AssetSource expects). The fight
  /// sounds are Kenney Impact Sounds (CC0, OGG); the menu blip is synthesized (tools/sfx_gen.py, WAV).
  /// See assets/sfx/CREDITS.md.
  static String assetFor(SfxKind k) =>
      k == SfxKind.select ? 'sfx/select.wav' : 'sfx/${k.name}.ogg';

  SfxBackend? _backend;
  bool _ready = false;
  bool _broken = false;

  /// Settings "Sound effects" off.
  bool muted = false;

  /// Errors swallowed so far (for tests and a debug line; never shown as a crash).
  int errors = 0;

  /// Sounds actually handed to the backend.
  int played = 0;

  /// True once [init] loaded every sound and nothing has failed since.
  bool get available => _ready && !_broken;

  /// Loads every sound through [backend]. Never throws; on any failure sound stays off this session.
  Future<void> init(SfxBackend Function() backend) async {
    if (_ready || _broken) return;
    try {
      final b = backend();
      for (final k in SfxKind.values) {
        await b.load(k, assetFor(k));
      }
      _backend = b;
      _ready = true;
    } catch (_) {
      errors++;
      _broken = true;
    }
  }

  /// Plays [kind] unless muted or unavailable. Fire-and-forget: never throws, never blocks the frame.
  void play(SfxKind kind) {
    if (muted || !available) return;
    final b = _backend!;
    played++;
    try {
      unawaited(
        b.play(kind).catchError((Object _) {
          _fail();
        }),
      );
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    errors++;
    // A few failures in a row (no audio device, audio service died): stop trying this session.
    if (errors >= 5) _broken = true;
  }

  void hit() => play(SfxKind.hit);
  void heavy() => play(SfxKind.heavy);
  void block() => play(SfxKind.block);
  void ko() => play(SfxKind.ko);
  void select() => play(SfxKind.select);
}

/// The app's one sound player.
final sfx = Sfx();
