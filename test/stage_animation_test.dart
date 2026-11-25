// Ticker-driven stage loop (lib/game/stage_animation.dart): frame selection
// from engine steps, and the animated-asset loader's missing-asset fallback.
// Runs without the animated binaries present: frames are in-memory images
// and the loader is exercised against assets that do not exist.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:plaza_brawler/art/fighter_painter.dart';
import 'package:plaza_brawler/game/stage_animation.dart';

/// A 1x1 transparent PNG, decoded in memory — no asset files needed.
Future<ui.Image> _pixel() async {
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  return ui.decodeImageFromList(base64Decode(png));
}

void main() {
  group('StageFrameSelector.frameIndex', () {
    test('starts on frame 0 and holds it for ticksPerFrame steps', () {
      expect(StageFrameSelector.frameIndex(step: 0, frameCount: 12), 0);
      expect(StageFrameSelector.frameIndex(step: 5, frameCount: 12), 0);
    });

    test('advances one frame per ticksPerFrame steps', () {
      expect(StageFrameSelector.frameIndex(step: 6, frameCount: 12), 1);
      expect(StageFrameSelector.frameIndex(step: 12, frameCount: 12), 2);
    });

    test('a 12-frame loop wraps after 72 steps (1.2 s at 60 Hz)', () {
      expect(StageFrameSelector.frameIndex(step: 71, frameCount: 12), 11);
      expect(StageFrameSelector.frameIndex(step: 72, frameCount: 12), 0);
      expect(StageFrameSelector.frameIndex(step: 144, frameCount: 12), 0);
    });

    test('no frames means frame 0', () {
      expect(StageFrameSelector.frameIndex(step: 42, frameCount: 0), 0);
      expect(StageFrameSelector.frameIndex(step: 42, frameCount: -1), 0);
    });
  });

  group('StageFrameSelector.frameFor', () {
    test('cycles through in-memory frames in order, then wraps', () async {
      final frames = [await _pixel(), await _pixel(), await _pixel()];
      expect(StageFrameSelector.frameFor(step: 0, frames: frames), frames[0]);
      expect(StageFrameSelector.frameFor(step: 6, frames: frames), frames[1]);
      expect(StageFrameSelector.frameFor(step: 12, frames: frames), frames[2]);
      expect(StageFrameSelector.frameFor(step: 18, frames: frames), frames[0]);
    });

    test('a single frame always paints, and empty means no frame', () async {
      final frames = [await _pixel()];
      expect(StageFrameSelector.frameFor(step: 999, frames: frames), frames[0]);
      expect(
        StageFrameSelector.frameFor(step: 0, frames: <ui.Image>[]),
        isNull,
      );
    });
  });

  group('stage loader fallback (no binaries present)', () {
    test('a missing animated asset decodes to no frames', () async {
      expect(
        await loadAnimatedStageImage('assets/stages/no_such_stage.webp'),
        isEmpty,
      );
    });

    test('a missing still decodes to null', () async {
      expect(
        await loadFighterSpriteImage('assets/stages/no_such_stage.jpg'),
        isNull,
      );
    });
  });
}
