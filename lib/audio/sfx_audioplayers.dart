// SfxBackend on the audioplayers package (MIT): one low-latency player per sound (Android SoundPool), mixed
// with other apps' audio instead of taking audio focus, so music or a call isn't interrupted. Errors are
// left to Sfx, which catches them all.
import 'package:audioplayers/audioplayers.dart';

import 'sfx.dart';

class AudioplayersBackend implements SfxBackend {
  final Map<SfxKind, AudioPlayer> _players = {};
  bool _contextSet = false;

  @override
  Future<void> load(SfxKind kind, String asset) async {
    if (!_contextSet) {
      _contextSet = true;
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
    }
    final p = AudioPlayer(playerId: 'sfx_${kind.name}');
    _players[kind] = p;
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setSource(AssetSource(asset));
  }

  @override
  Future<void> play(SfxKind kind) async {
    final p = _players[kind];
    if (p == null) return;
    await p.stop();
    await p.resume();
  }
}
