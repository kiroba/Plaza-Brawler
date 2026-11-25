/// Ticker-driven stage animation (Slice 1, Nov 25, 2026): the painted stage
/// backdrop is a looping animated asset (assets/stages/*.webp, 12 frames).
/// Frames advance on engine steps, never on wall clock, so both PvP sides
/// step the same frames from the same lockstepped engine — and a paused or
/// hit-stopped fight freezes the stage with everything else.
library;

import 'dart:ui' as ui;

/// Pure frame selection for a looping stage asset.
class StageFrameSelector {
  /// Engine steps per stage frame. The engine ticks at 60 Hz, so 6 steps
  /// per frame plays a 12-frame loop in 1.2 s — the asset's own frame
  /// duration (100 ms).
  static const int ticksPerFrame = 6;

  /// Frame index for engine step [step] in a loop of [frameCount] frames.
  /// 0 when there is nothing to play.
  static int frameIndex({required int step, required int frameCount}) {
    if (frameCount <= 0) return 0;
    return (step ~/ ticksPerFrame) % frameCount;
  }

  /// The frame to paint at engine step [step], or null when [frames] is
  /// empty (the caller falls back to the still, then the gradient).
  static ui.Image? frameFor({
    required int step,
    required List<ui.Image> frames,
  }) {
    if (frames.isEmpty) return null;
    return frames[frameIndex(step: step, frameCount: frames.length)];
  }
}
