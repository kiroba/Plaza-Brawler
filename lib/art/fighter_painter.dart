// Placeholder arena + fighter art (spec 4.11): simple tinted shapes from FighterDef colours and its
// 5-layer manifest tints (body, palette, outfit, accessory, aura), posed by FighterAction.
// Real: everything drawn here. Stubbed: the Kaggle FLUX sprites; when they land, a sprite resolver swaps
// PNGs in by asset_id (not part of this build).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/fighter.dart';
import '../game/match_engine.dart';

/// Draws the arena, both fighters, projectiles and hit flashes for one [MatchEngine] frame.
class ArenaPainter extends CustomPainter {
  final MatchEngine engine;

  /// Frame counters set by the screen when a hit lands (white flash on that side).
  final List<int> flash;

  /// Screen shake offset in arena px.
  final Offset shake;

  /// Decoded three-quarter pack sprites by asset path, for fighters whose
  /// def carries a sprite binding. A missing entry paints the fighter as
  /// before, so a sprite that fails to load never breaks a match.
  final Map<String, ui.Image> spriteImages;

  ArenaPainter({
    required this.engine,
    required this.flash,
    this.shake = Offset.zero,
    this.spriteImages = const {},
  }) : super();

  static const double _groundFrac = 0.82;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / MatchEngine.arenaWidth,
      size.height / MatchEngine.arenaHeight,
    );
    final w = MatchEngine.arenaWidth * scale,
        h = MatchEngine.arenaHeight * scale;
    final origin = Offset((size.width - w) / 2, (size.height - h) / 2);

    canvas.save();
    canvas.translate(
      origin.dx + shake.dx * scale,
      origin.dy + shake.dy * scale,
    );
    canvas.scale(scale);
    _background(canvas);
  const groundY = MatchEngine.arenaHeight * _groundFrac;
    for (final p in engine.projectiles) {
      final paint = Paint()
        ..color = const Color(0xFF4CC9F0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(p.x, groundY - p.y - 40), 12, paint);
      canvas.drawCircle(
        Offset(p.x, groundY - p.y - 40),
        7,
        Paint()..color = Colors.white70,
      );
    }
    paintFighter(
      canvas,
      engine.p2,
      groundY,
      flash.length > 1 && flash[1] > 0,
      sprite: engine.p2.def.sprite == null
          ? null
          : spriteImages[engine.p2.def.sprite!.bodyAsset],
    );
    paintFighter(
      canvas,
      engine.p1,
      groundY,
      flash.isNotEmpty && flash[0] > 0,
      sprite: engine.p1.def.sprite == null
          ? null
          : spriteImages[engine.p1.def.sprite!.bodyAsset],
    );
    canvas.restore();
  }

  void _background(Canvas canvas) {
    const r = Rect.fromLTWH(
      0,
      0,
      MatchEngine.arenaWidth,
      MatchEngine.arenaHeight,
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A2E), Color(0xFF2A1F3D)],
        ).createShader(r),
    );
  const groundY = MatchEngine.arenaHeight * _groundFrac;
    canvas.drawRect(
      const Rect.fromLTWH(
        0,
        groundY,
        MatchEngine.arenaWidth,
        MatchEngine.arenaHeight - groundY,
      ),
      Paint()..color = const Color(0xFF1E293B),
    );
    canvas.drawLine(
      const Offset(0, groundY),
      const Offset(MatchEngine.arenaWidth, groundY),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 2,
    );
  }

  static Color _layerTint(FighterDef d, String layer, Color fallback) {
    for (final l in d.layers) {
      if (l.layer == layer) {
        return Color(l.tint)
            .withValues(alpha: (l.opacity.clamp(0, 100)) / 100.0);
      }
    }
    return fallback;
  }

  static void paintFighter(
    Canvas canvas,
    FighterState f,
    double groundY,
    bool flashing, {
    ui.Image? sprite,
  }) {
    final d = f.def;
    final primary = Color(d.primary);
    final body = flashing ? Colors.white : _layerTint(d, 'body', primary);
    final outfit = flashing
        ? Colors.white
        : _layerTint(d, 'outfit', Color.lerp(primary, Colors.black, 0.35)!);
    final aura = _layerTint(d, 'aura', primary);
    final accessory = _layerTint(d, 'accessory', const Color(0xFFFFD700));

    canvas.save();
    canvas.translate(f.x, groundY - f.y);
    if (!f.facingRight) canvas.scale(-1, 1);

    if (f.action == FighterAction.ko) {
      canvas.rotate(-math.pi / 2);
      canvas.translate(-10, 0);
    } else if (f.action == FighterAction.hitstun) {
      canvas.rotate(-0.18);
    }

    // Aura glow (bigger during a special).
    final auraR = f.action == FighterAction.special ? 62.0 : 44.0;
    canvas.drawCircle(
      const Offset(0, -48),
      auraR,
      Paint()
        ..color = aura.withValues(
          alpha: f.action == FighterAction.special ? 0.45 : 0.18,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Pack sprite body: one static image, posed by transform the way the
    // painted fighter reads (translation already applied above; walk bobs,
    // attacks lunge, blocks tuck). The hit flash whitens it like the painted
    // body. Blocking keeps the shield arc drawn below.
    if (sprite != null) {
      var dx = 0.0;
      var dy = 0.0;
      if (f.action == FighterAction.walk) {
        dy = -math.sin(f.actionFrames * 0.4).abs() * 3;
      } else if (f.action == FighterAction.light ||
          f.action == FighterAction.heavy) {
        dx = 7;
      } else if (f.action == FighterAction.special) {
        dx = 4;
        dy = -3;
      } else if (f.action == FighterAction.block) {
        dx = -3;
      }
      const h = 116.0;
      final dst = Rect.fromLTWH(-h / 2 + dx, -h + 3 + dy, h, h);
      final paint = Paint();
      if (flashing) {
        paint.colorFilter = const ColorFilter.matrix(<double>[
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255, //
          0, 0, 0, 1, 0,
        ]);
      }
      canvas.drawImageRect(
        sprite,
        Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
        dst,
        paint,
      );
      if (f.blocking) {
        canvas.drawArc(
          const Rect.fromLTWH(4, -100, 40, 80),
          -math.pi / 2.6,
          math.pi / 1.3,
          false,
          Paint()
            ..color = const Color(0xAA00E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
      canvas.restore();
      return;
    }

    final limb = Paint()
      ..color = body
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final leg = Paint()
      ..color = outfit
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final airborne = f.y > 1 || f.action == FighterAction.jump;
    final bob = f.action == FighterAction.walk
        ? math.sin(f.actionFrames * 0.4) * 6
        : 0.0;

    // Legs.
    if (f.action == FighterAction.heavy) {
      canvas.drawLine(const Offset(0, -34), const Offset(-10, 0), leg);
      canvas.drawLine(const Offset(0, -34), const Offset(44, -30), leg); // kick
    } else if (airborne) {
      canvas.drawLine(const Offset(0, -34), const Offset(-12, -14), leg);
      canvas.drawLine(const Offset(0, -34), const Offset(12, -18), leg);
    } else {
      canvas.drawLine(const Offset(0, -34), Offset(-10 - bob, 0), leg);
      canvas.drawLine(const Offset(0, -34), Offset(10 + bob, 0), leg);
    }

    // Torso.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-14, -76, 28, 44),
        const Radius.circular(8),
      ),
      Paint()..color = outfit,
    );

    // Arms.
    switch (f.action) {
      case FighterAction.light:
        canvas.drawLine(const Offset(4, -66), const Offset(42, -64), limb);
        canvas.drawLine(const Offset(-4, -66), const Offset(-12, -46), limb);
        break;
      case FighterAction.special:
        canvas.drawLine(const Offset(4, -66), const Offset(40, -70), limb);
        canvas.drawLine(const Offset(-4, -66), const Offset(30, -58), limb);
        canvas.drawCircle(const Offset(44, -68), 9, Paint()..color = aura);
        break;
      case FighterAction.block:
        canvas.drawLine(const Offset(6, -70), const Offset(18, -86), limb);
        canvas.drawLine(const Offset(6, -58), const Offset(20, -70), limb);
        break;
      default:
        canvas.drawLine(const Offset(4, -66), Offset(16, -44 + bob), limb);
        canvas.drawLine(const Offset(-4, -66), Offset(-14, -44 - bob), limb);
    }

    // Head + accessory band + eye (shows facing).
    canvas.drawCircle(const Offset(0, -90), 13, Paint()..color = body);
    canvas.drawRect(
      const Rect.fromLTWH(-13, -98, 26, 5),
      Paint()..color = accessory,
    );
    canvas.drawCircle(const Offset(6, -90), 2.5, Paint()..color = Colors.black);

    if (f.blocking) {
      canvas.drawArc(
        const Rect.fromLTWH(4, -100, 40, 80),
        -math.pi / 2.6,
        math.pi / 1.3,
        false,
        Paint()
          ..color = const Color(0xAA00E5FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ArenaPainter oldDelegate) => true;
}

/// A fighter standing still, for menus, character select and the VS splash.
class FighterPortrait extends StatelessWidget {
  final FighterDef def;
  final double size;
  final bool facingRight;

  const FighterPortrait({
    super.key,
    required this.def,
    this.size = 80,
    this.facingRight = true,
  });

  @override
  Widget build(BuildContext context) {
    final binding = def.sprite;
    if (binding == null) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PortraitPainter(def, facingRight)),
      );
    }
    // Pack portrait. Any load failure falls back to the painted portrait —
    // the binding is an enhancement, never a dependency.
    final painted = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PortraitPainter(def, facingRight)),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Transform.flip(
        flipX: !facingRight,
        child: Image.asset(
          binding.portraitAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => painted,
        ),
      ),
    );
  }
}

/// Decodes a bundled asset image for the arena painter. Null on any
/// failure — callers treat a missing sprite as "painted fighter".
Future<ui.Image?> loadFighterSpriteImage(String asset) async {
  try {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

class _PortraitPainter extends CustomPainter {
  final FighterDef def;
  final bool facingRight;
  _PortraitPainter(this.def, this.facingRight);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 130;
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.95);
    canvas.scale(s);
    final state = FighterState(def, x: 0, facingRight: facingRight);
    ArenaPainter.paintFighter(canvas, state, 0, false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter old) =>
      old.def != def || old.facingRight != facingRight;
}
