// Sound effects wrapper (lib/audio/sfx.dart): mute, and sound never crashes the game. Pure Dart.
import 'package:plaza_brawler/audio/sfx.dart';
import 'package:test/test.dart';

class _Fake implements SfxBackend {
  final bool failLoad;
  final bool failPlay;
  final bool throwSync;
  final loaded = <String>[];
  final playedKinds = <SfxKind>[];
  _Fake({this.failLoad = false, this.failPlay = false, this.throwSync = false});

  @override
  Future<void> load(SfxKind kind, String asset) async {
    if (failLoad) throw StateError('no audio device');
    loaded.add(asset);
  }

  @override
  Future<void> play(SfxKind kind) {
    if (throwSync) throw StateError('sync boom');
    playedKinds.add(kind);
    return failPlay ? Future.error(StateError('async boom')) : Future.value();
  }
}

void main() {
  test('loads all four sounds from assets/sfx and plays them', () async {
    final b = _Fake();
    final s = Sfx();
    await s.init(() => b);
    expect(s.available, isTrue);
    expect(b.loaded, [
      'sfx/hit.wav',
      'sfx/block.wav',
      'sfx/ko.wav',
      'sfx/select.wav',
    ]);
    s
      ..hit()
      ..block()
      ..ko()
      ..select();
    expect(b.playedKinds, [
      SfxKind.hit,
      SfxKind.block,
      SfxKind.ko,
      SfxKind.select,
    ]);
  });

  test('muted: nothing plays', () async {
    final b = _Fake();
    final s = Sfx()..muted = true;
    await s.init(() => b);
    s.hit();
    s.select();
    expect(b.playedKinds, isEmpty);
    s.muted = false;
    s.hit();
    expect(b.playedKinds, [SfxKind.hit]);
  });

  test(
    'backend that cannot start: init and play never throw, sound stays off',
    () async {
      final s = Sfx();
      await s.init(() => _Fake(failLoad: true));
      expect(s.available, isFalse);
      s.hit();
      expect(s.played, 0);
      final s2 = Sfx();
      await s2.init(() => throw UnsupportedError('no plugin'));
      expect(s2.available, isFalse);
      s2.ko();
    },
  );

  test(
    'play errors (sync or async) are swallowed; repeated ones switch sound off',
    () async {
      final s = Sfx();
      await s.init(() => _Fake(failPlay: true));
      for (var i = 0; i < 4; i++) {
        s.hit();
      }
      await Future<void>.delayed(Duration.zero);
      expect(s.errors, 4);
      expect(s.available, isTrue);
      s.hit();
      await Future<void>.delayed(Duration.zero);
      expect(s.available, isFalse);
      s.hit(); // no-op now
      expect(s.played, 5);

      final t = Sfx();
      await t.init(() => _Fake(throwSync: true));
      expect(() => t.select(), returnsNormally);
      expect(t.errors, 1);
    },
  );

  test('asset paths are assets/sfx/<name>.wav (as listed in pubspec.yaml)', () {
    for (final k in SfxKind.values) {
      expect(Sfx.assetFor(k), 'sfx/${k.name}.wav');
    }
  });
}
