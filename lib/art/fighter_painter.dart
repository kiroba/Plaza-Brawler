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
import '../game/specials.dart';

/// Draws the arena, both fighters, projectiles and hit flashes for one [MatchEngine] frame.
class ArenaPainter extends CustomPainter {
  final MatchEngine engine;

  /// Frame counters set by the screen when a hit lands (white flash on that side).
  final List<int> flash;

  /// Screen shake offset in arena px.
  final Offset shake;

  /// Element spark bursts (S4): frames left and tint per side, set by the
  /// screen when a basic (non-special) hit lands — the defender sparks in a
  /// faint tint of the ATTACKER's element.
  final List<int> sparkFrames;
  final List<Color> sparkColors;

  /// Decoded three-quarter pack sprites by asset path, for fighters whose
  /// def carries a sprite binding. A missing entry paints the fighter as
  /// before, so a sprite that fails to load never breaks a match.
  final Map<String, ui.Image> spriteImages;

  /// Painted stage backdrop for this match (see Stages in
  /// lib/game/stages.dart). Null paints the placeholder gradient, so
  /// a stage that fails to load never breaks a match.
  final ui.Image? stageImage;

  ArenaPainter({
    required this.engine,
    required this.flash,
    this.shake = Offset.zero,
    this.spriteImages = const {},
    this.stageImage,
    this.sparkFrames = const [0, 0],
    this.sparkColors = const [Colors.white, Colors.white],
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
    for (final z in engine.zones) {
      canvas.drawCircle(
        Offset(z.x, groundY - 4),
        50,
        Paint()..color = const Color(0xFF4CC9F0).withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        Offset(z.x, groundY - 4),
        30,
        Paint()..color = const Color(0xFF4CC9F0).withValues(alpha: 0.30),
      );
    }
    for (final p in engine.projectiles) {
      final def = Specials.byId(p.specialId);
      final color = Color(Specials.colorOf(def.element));
      if (def.kind == SpecialKind.groundCrack) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(p.x, groundY - 3),
            width: 40,
            height: 9,
          ),
          Paint()..color = color,
        );
        continue;
      }
      final paint = Paint()
        ..color = color
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
    for (var side = 0; side < 2; side++) {
      if (side >= sparkFrames.length || sparkFrames[side] <= 0) continue;
      final f = side == 0 ? engine.p1 : engine.p2;
      final alpha = (sparkFrames[side] / 5).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = sparkColors[side].withValues(alpha: 0.75 * alpha)
        ..strokeWidth = 2.5;
      final cx = f.x, cy = groundY - f.y - 72;
      canvas.drawLine(Offset(cx - 4, cy), Offset(cx - 16, cy - 9), paint);
      canvas.drawLine(Offset(cx + 3, cy - 4), Offset(cx + 15, cy - 14), paint);
      canvas.drawLine(Offset(cx, cy + 3), Offset(cx + 10, cy + 12), paint);
    }
    canvas.restore();
  }

  void _background(Canvas canvas) {
    const r = Rect.fromLTWH(
      0,
      0,
      MatchEngine.arenaWidth,
      MatchEngine.arenaHeight,
    );
    final stage = stageImage;
    if (stage != null) {
      // Cover-fit: centre-crop the source to the arena's aspect so
      // wider or taller art never distorts.
      final srcAspect = stage.width / stage.height;
      const dstAspect = MatchEngine.arenaWidth / MatchEngine.arenaHeight;
      var sw = stage.width.toDouble();
      var sh = stage.height.toDouble();
      if (srcAspect > dstAspect) {
        sw = sh * dstAspect;
      } else {
        sh = sw / dstAspect;
      }
      final src = Rect.fromLTWH(
        (stage.width - sw) / 2,
        (stage.height - sh) / 2,
        sw,
        sh,
      );
      canvas.drawImageRect(stage, src, r, Paint());
      return;
    }
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

    // Aura glow (bigger during a special; full element colour and size on
    // an Elemental Finish, S3).
    final elemental =
        f.action == FighterAction.special && f.finisher == 'elemental';
    final auraR = elemental
        ? 80.0
        : (f.action == FighterAction.special ? 62.0 : 44.0);
    canvas.drawCircle(
      const Offset(0, -48),
      auraR,
      Paint()
        ..color = aura.withValues(
          alpha: elemental
              ? 0.85
              : (f.action == FighterAction.special ? 0.45 : 0.18),
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
      } else if (f.action == FighterAction.hp ||
          f.action == FighterAction.lp ||
          f.action == FighterAction.hk ||
          f.action == FighterAction.lk) {
        dx = 7;
      } else if (f.action == FighterAction.throwing) {
        dx = 5;
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
    // Crouching drops the whole upper body (S1 stance pose).
    final crouchDrop = f.crouching ? 14.0 : 0.0;
    final bob = f.action == FighterAction.walk
        ? math.sin(f.actionFrames * 0.4) * 6
        : 0.0;

    // Legs.
    if (f.action == FighterAction.hk || f.action == FighterAction.lk) {
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
        Rect.fromLTWH(-14, -76 + crouchDrop, 28, 44),
        const Radius.circular(8),
      ),
      Paint()..color = outfit,
    );

    // Arms (punch pose for HP/LP; kicks keep the guard-ish default).
    switch (f.action) {
      case FighterAction.hp:
      case FighterAction.lp:
        canvas.drawLine(
            Offset(4, -66 + crouchDrop), Offset(42, -64 + crouchDrop), limb);
        canvas.drawLine(Offset(-4, -66 + crouchDrop),
            Offset(-12, -46 + crouchDrop), limb);
        break;
      case FighterAction.special:
        canvas.drawLine(
            Offset(4, -66 + crouchDrop), Offset(40, -70 + crouchDrop), limb);
        canvas.drawLine(Offset(-4, -66 + crouchDrop),
            Offset(30, -58 + crouchDrop), limb);
        canvas.drawCircle(
            Offset(44, -68 + crouchDrop), 9, Paint()..color = aura);
        break;
      case FighterAction.throwing:
        // Both arms reach out for the grab.
        canvas.drawLine(
            Offset(4, -66 + crouchDrop), Offset(38, -62 + crouchDrop), limb);
        canvas.drawLine(Offset(-4, -66 + crouchDrop),
            Offset(30, -52 + crouchDrop), limb);
        break;
      case FighterAction.block:
        canvas.drawLine(
            Offset(6, -70 + crouchDrop), Offset(18, -86 + crouchDrop), limb);
        canvas.drawLine(
            Offset(6, -58 + crouchDrop), Offset(20, -70 + crouchDrop), limb);
        break;
      default:
        canvas.drawLine(
            Offset(4, -66 + crouchDrop), Offset(16, -44 + bob + crouchDrop),
            limb);
        canvas.drawLine(Offset(-4, -66 + crouchDrop),
            Offset(-14, -44 - bob + crouchDrop), limb);
    }

    // Head + accessory band + eye (shows facing).
    canvas.drawCircle(Offset(0, -90 + crouchDrop), 13, Paint()..color = body);
    canvas.drawRect(
      Rect.fromLTWH(-13, -98 + crouchDrop, 26, 5),
      Paint()..color = accessory,
    );
    canvas.drawCircle(
        Offset(6, -90 + crouchDrop), 2.5, Paint()..color = Colors.black);

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
