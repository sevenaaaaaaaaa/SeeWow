import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The SeeWow mark: a play shard cut from liquid glass, throwing light.
///
/// Three ideas, one silhouette. The rounded triangle is playback. Its material
/// is glass — lit from the upper left, bending a faint spectrum along the cut
/// edge the way a real pane bends a projector beam. The spark at the apex is
/// the part that makes the mark about *watching with something intelligent*
/// rather than about a player: light leaves the frame instead of stopping at
/// it.
///
/// The silhouette is deliberately a **soft shard**, not the stock hard play
/// triangle: a thick left spine, a lens-shaped apex, unequal corner radii. At
/// 16 px it still reads as play, and it can never be mistaken for another
/// app's icon.
///
/// Everything is painted from [WowMarkPainter] in a fixed 1024-unit design
/// space. App icons, the in-app mark and the splash come out of this one
/// source, so the brand cannot drift between them.
class WowMark extends StatelessWidget {
  const WowMark({
    super.key,
    this.size = 32,
    this.tile = false,
    this.monochrome = false,
    this.color,
    this.tileRadius,
    this.phase = 0,
  });

  final double size;

  /// Paint the dark plate behind the mark. In-app headers keep it off and
  /// supply their own surface.
  final bool tile;

  /// Single-colour cut for places that must follow the skin's accent.
  final bool monochrome;

  final Color? color;

  /// Corner radius of the plate as a fraction of [size]. Null uses the Apple
  /// icon-grid squircle ratio.
  final double? tileRadius;

  /// Phase offset for the spark, so several marks never twinkle in lockstep.
  final double phase;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: WowMarkPainter(
          tile: tile,
          monochrome: monochrome,
          color: color,
          tileRadius: tileRadius,
          phase: phase,
        ),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

/// Paints the mark. Design space is 1024 x 1024, so every constant reads as
/// a coordinate rather than as a ratio.
class WowMarkPainter extends CustomPainter {
  const WowMarkPainter({
    this.tile = false,
    this.monochrome = false,
    this.color,
    this.tileRadius,
    this.phase = 0,
  });

  final bool tile;
  final bool monochrome;
  final Color? color;
  final double? tileRadius;
  final double phase;

  static const double _design = 1024;

  /// Apple's icon-grid squircle ratio for a 1024 plate.
  static const double _squircle = 0.2237;

  // The shard: thick left spine, apex pulled into a lens.
  static const Offset _a = Offset(334, 268);
  static const Offset _b = Offset(334, 756);
  static const Offset _c = Offset(792, 512);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = size.shortestSide / _design;
    canvas.save();
    canvas.translate(
      (size.width - _design * s) / 2,
      (size.height - _design * s) / 2,
    );
    canvas.scale(s);
    final ink = color ?? const Color(0xFFF6F7FB);
    if (tile) paintPlate(canvas);
    if (!tile && !monochrome) _paintHalo(canvas);
    if (!monochrome) _paintBeam(canvas);
    _paintShard(canvas, ink);
    _paintSpark(canvas, ink);
    canvas.restore();
  }

  /// The plate: graphite with the light already pooling behind the shard.
  void paintPlate(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, _design, _design);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(_design * (tileRadius ?? _squircle)),
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, _design),
          const [Color(0xFF191B21), Color(0xFF07080A)],
          const [0, 1],
        ),
    );
    _paintHalo(canvas);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(512, 470),
          760,
          [const Color(0x00000000), Colors.black.withValues(alpha: .40)],
          const [.52, 1],
        ),
    );
    // Rim: the plate is itself a pane of glass, so its edge catches light.
    if (tileRadius != 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(2.2),
          Radius.circular(_design * (tileRadius ?? _squircle) - 2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(_design, _design),
            [
              Colors.white.withValues(alpha: .18),
              Colors.white.withValues(alpha: .03),
              Colors.white.withValues(alpha: .10),
            ],
            const [0, .55, 1],
          ),
      );
    }
    canvas.restore();
  }

  /// Light behind the glass. Two pools: a cool one where the beam enters, a
  /// warmer one at the shadow side, so the plate never reads as flat grey.
  void _paintHalo(Canvas canvas) {
    canvas.drawCircle(
      const Offset(590, 452),
      470,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(590, 452),
          470,
          [
            const Color(0xFFADD0FF).withValues(alpha: .22),
            const Color(0xFF6E8CFF).withValues(alpha: .06),
            const Color(0x00000000),
          ],
          const [0, .44, 1],
        ),
    );
    canvas.drawCircle(
      const Offset(286, 774),
      360,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(286, 774),
          360,
          [
            const Color(0xFF8FE6FF).withValues(alpha: .09),
            const Color(0x00000000),
          ],
          const [0, 1],
        ),
    );
  }

  /// Light leaving the apex — a bloom and one thin streak, never a cone.
  ///
  /// The first attempt did use a cone, and at 128 px it read as a grey smudge
  /// sliding out of the shard: a hard edge against the plate is what turns
  /// light into dirt. A radial bloom has no edge anywhere, so it survives
  /// every size, and the single streak carries the direction.
  void _paintBeam(Canvas canvas) {
    final apex = Offset(_c.dx + 26, _c.dy);
    canvas.drawCircle(
      apex,
      228,
      Paint()
        ..shader = ui.Gradient.radial(
          apex,
          228,
          [
            Colors.white.withValues(alpha: .22),
            const Color(0xFFC9DCFF).withValues(alpha: .07),
            const Color(0x00FFFFFF),
          ],
          const [0, .34, 1],
        ),
    );
  }

  /// The glass body: a gradient with a readable light side, a refraction band,
  /// a specular sheet along the cut, and a rim that dies on the shadow edge.
  void _paintShard(Canvas canvas, Color ink) {
    final path = shardPath();

    // Contact shadow: glass has thickness, so it sits *on* the plate.
    if (!monochrome) {
      canvas.save();
      canvas.translate(0, 16);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: .38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(300, 200),
          const Offset(860, 820),
          monochrome
              ? [ink, ink.withValues(alpha: .90)]
              : [
                  Colors.white,
                  const Color(0xFFF7FAFF).withValues(alpha: .97),
                  const Color(0xFFDCE7FC).withValues(alpha: .88),
                ],
          monochrome ? const [0, 1] : const [0, .5, 1],
        ),
    );

    if (!monochrome) {
      canvas.save();
      canvas.clipPath(path);
      // Refraction: a cool band where the beam crosses the glass, warm on the
      // opposite edge. Low alphas, so the mark stays a monochrome icon with a
      // temperature instead of becoming a rainbow.
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            const Offset(700, 300),
            const Offset(400, 780),
            [
              const Color(0xFF9BE7FF).withValues(alpha: .26),
              const Color(0x00000000),
              const Color(0xFFFFC7E8).withValues(alpha: .13),
            ],
            const [0, .45, 1],
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(350, 250),
            const Offset(660, 720),
            [
              Colors.white.withValues(alpha: .48),
              Colors.white.withValues(alpha: .04),
              const Color(0x00000000),
            ],
            const [0, .34, .84],
          ),
      );
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = ui.Gradient.linear(
          const Offset(300, 180),
          const Offset(820, 860),
          monochrome
              ? [ink, ink.withValues(alpha: .45)]
              : [
                  Colors.white,
                  Colors.white.withValues(alpha: .52),
                  Colors.white.withValues(alpha: .10),
                ],
          monochrome ? const [0, 1] : const [0, .5, 1],
        ),
    );

    // Wet edge: the brightest thing on real glass is the 2 px where the
    // surface meets air. It is what makes the shard look polished rather
    // than matte, and it is the detail that survives into a 29 px icon.
    if (!monochrome) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            const Offset(320, 230),
            const Offset(760, 800),
            [
              Colors.white,
              Colors.white.withValues(alpha: .35),
              const Color(0x00FFFFFF),
            ],
            const [0, .30, .62],
          ),
      );
    }

    // Inner bevel. Glass has thickness: a bright inner edge on the lit side
    // and a dark one on the shadow side are what stop the shard from reading
    // as a white sticker cut out of paper.
    if (!monochrome) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..shader = ui.Gradient.linear(
            const Offset(330, 210),
            const Offset(790, 830),
            [Colors.white.withValues(alpha: .50), const Color(0x00FFFFFF)],
            const [0, .60],
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..shader = ui.Gradient.linear(
            const Offset(800, 840),
            const Offset(430, 320),
            [
              Colors.black.withValues(alpha: .09),
              const Color(0x00000000),
            ],
            const [0, .60],
          ),
      );
      canvas.restore();
    }
  }

  /// The silhouette. Corner radii are unequal on purpose: equal radii turn the
  /// shape back into the stock play button. Corners are quadratic through the
  /// vertex, which gives a parabolic — softly superelliptic — corner instead
  /// of a circle bolted onto a triangle.
  Path shardPath() {
    const rA = 168.0;
    const rB = 150.0;
    const rC = 214.0;
    final exitA = _toward(_a, _b, rA);
    final entryB = _toward(_b, _a, rB);
    final exitB = _toward(_b, _c, rB);
    final entryC = _toward(_c, _b, rC);
    final exitC = _toward(_c, _a, rC);
    final entryA = _toward(_a, _c, rA);

    return Path()
      ..moveTo(exitA.dx, exitA.dy)
      ..lineTo(entryB.dx, entryB.dy)
      ..quadraticBezierTo(_b.dx, _b.dy, exitB.dx, exitB.dy)
      ..lineTo(entryC.dx, entryC.dy)
      ..quadraticBezierTo(_c.dx, _c.dy, exitC.dx, exitC.dy)
      ..lineTo(entryA.dx, entryA.dy)
      ..quadraticBezierTo(_a.dx, _a.dy, exitA.dx, exitA.dy)
      ..close();
  }

  Offset _toward(Offset from, Offset to, double distance) {
    final d = to - from;
    final len = d.distance;
    if (len == 0) return from;
    return from + d / len * distance;
  }

  /// A four-point spark at the apex: the one non-geometric shape in the mark,
  /// and the reason the icon reads as "something is happening here".
  void _paintSpark(Canvas canvas, Color ink) {
    final centre = Offset(
      846 + math.cos(phase) * 3,
      388 + math.sin(phase) * 3,
    );
    const long = 74.0;
    const thin = 14.5;
    final spark = Path()
      ..moveTo(centre.dx, centre.dy - long)
      ..quadraticBezierTo(
        centre.dx + thin,
        centre.dy - thin,
        centre.dx + long,
        centre.dy,
      )
      ..quadraticBezierTo(
        centre.dx + thin,
        centre.dy + thin,
        centre.dx,
        centre.dy + long,
      )
      ..quadraticBezierTo(
        centre.dx - thin,
        centre.dy + thin,
        centre.dx - long,
        centre.dy,
      )
      ..quadraticBezierTo(
        centre.dx - thin,
        centre.dy - thin,
        centre.dx,
        centre.dy - long,
      )
      ..close();

    if (!monochrome) {
      canvas.drawCircle(
        centre,
        150,
        Paint()
          ..shader = ui.Gradient.radial(centre, 150, [
            const Color(0xFFE8F2FF).withValues(alpha: .34),
            const Color(0x00000000),
          ]),
      );
    }
    canvas.drawPath(spark, Paint()..color = monochrome ? ink : Colors.white);

    final small = Offset(centre.dx + 76, centre.dy + 74);
    canvas.drawPath(
      Path()
        ..moveTo(small.dx, small.dy - 26)
        ..quadraticBezierTo(small.dx + 5, small.dy - 5, small.dx + 26, small.dy)
        ..quadraticBezierTo(small.dx + 5, small.dy + 5, small.dx, small.dy + 26)
        ..quadraticBezierTo(small.dx - 5, small.dy + 5, small.dx - 26, small.dy)
        ..quadraticBezierTo(small.dx - 5, small.dy - 5, small.dx, small.dy - 26)
        ..close(),
      Paint()..color = (monochrome ? ink : Colors.white).withValues(alpha: .70),
    );
  }

  @override
  bool shouldRepaint(WowMarkPainter old) =>
      old.tile != tile ||
      old.monochrome != monochrome ||
      old.color != color ||
      old.tileRadius != tileRadius ||
      old.phase != phase;
}
