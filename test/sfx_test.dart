// Sound effects wrapper (lib/audio/sfx.dart): mute, and sound never crashes the game. Pure Dart.
import 'package:plaza_brawler/audio/sfx.dart';
import 'package:plaza_brawler/game/hit_feel.dart';
import 'package:plaza_brawler/game/match_engine.dart';
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
  test('loads all five sounds from assets/sfx and plays them', () async {
    final b = _Fake();
    final s = Sfx();
    await s.init(() => b);
    expect(s.available, isTrue);
    expect(b.loaded, [
      'sfx/hit.ogg',
      'sfx/heavy.ogg',
      'sfx/block.ogg',
      'sfx/ko.ogg',
      'sfx/select.wav',
    ]);
    s
      ..hit()
      ..heavy()
      ..block()
      ..ko()
      ..select();
    expect(b.playedKinds, [
      SfxKind.hit,
      SfxKind.heavy,
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

  test(
    'asset paths: Kenney OGGs for fight sounds, synth WAV for menu select',
    () {
      for (final k in SfxKind.values) {
        expect(
          Sfx.assetFor(k),
          k == SfxKind.select ? 'sfx/select.wav' : 'sfx/${k.name}.ogg',
        );
      }
    },
  );

  group('HitFeel.soundsFor (which cue a frame plays)', () {
    HitFx fx({
      bool blocked = false,
      bool heavy = false,
      bool special = false,
      bool guardBreak = false,
      bool ko = false,
    }) => HitFx(
      defender: 1,
      blocked: blocked,
      heavy: heavy,
      special: special,
      guardBreak: guardBreak,
      ko: ko,
    );

    test('nothing happened: no sound', () {
      expect(HitFeel.soundsFor(const []), isEmpty);
    });

    test('landed light hit: light hit sound', () {
      expect(HitFeel.soundsFor([fx()]), [SfxKind.hit]);
    });

    test('landed heavy, special (Flare Rush) and guard break: heavy sound', () {
      expect(HitFeel.soundsFor([fx(heavy: true)]), [SfxKind.heavy]);
      expect(HitFeel.soundsFor([fx(special: true)]), [SfxKind.heavy]);
      expect(HitFeel.soundsFor([fx(blocked: true, guardBreak: true)]), [
        SfxKind.heavy,
      ]);
    });

    test('blocked hit (heavy or light): block sound only', () {
      expect(HitFeel.soundsFor([fx(blocked: true)]), [SfxKind.block]);
      expect(HitFeel.soundsFor([fx(blocked: true, heavy: true)]), [
        SfxKind.block,
      ]);
      expect(HitFeel.soundsFor([fx(blocked: true, special: true)]), [
        SfxKind.block,
      ]);
    });

    test('at most one of each per frame; heavy wins over light', () {
      // Flare Rush landing twice in one frame.
      expect(HitFeel.soundsFor([fx(special: true), fx(special: true)]), [
        SfxKind.heavy,
      ]);
      expect(HitFeel.soundsFor([fx(), fx(heavy: true)]), [SfxKind.heavy]);
      expect(HitFeel.soundsFor([fx(), fx()]), [SfxKind.hit]);
      // Traded hits: one landed, one blocked.
      expect(HitFeel.soundsFor([fx(), fx(blocked: true)]), [
        SfxKind.hit,
        SfxKind.block,
      ]);
    });

    test('KO plays only the KO sound', () {
      expect(
        HitFeel.soundsFor([fx(heavy: true, ko: true), fx(blocked: true)]),
        [SfxKind.ko],
      );
      expect(HitFeel.soundsFor([fx(ko: true)]), [SfxKind.ko]);
    });
  });
}
