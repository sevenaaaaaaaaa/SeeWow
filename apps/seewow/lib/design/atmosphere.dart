import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

/// Ambient light distilled from artwork + film grain + vignette.
///
/// The amount of colour is decided by the running backdrop preset: colour fog,
/// neutral vignette, tonal wash or flat ink.
class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key, this.hue, this.child});

  final Color? hue;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final mode = WowSkin.I.backdropId;
    final tint = hue ?? WowColors.ambient;
    final glow = Color.lerp(tint, Colors.white, 0.18)!;

    return DecoratedBox(
      decoration: BoxDecoration(color: WowColors.ink),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (mode == WowBackdropId.fog) ...[
            Positioned(
              left: -220,
              top: -260,
              child: _Glow(color: glow.withValues(alpha: 0.34), size: 760),
            ),
            Positioned(
              right: -180,
              bottom: -240,
              child: _Glow(color: WowColors.accent.withValues(alpha: 0.18), size: 720),
            ),
          ],
          if (mode == WowBackdropId.vignette)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.1,
                  colors: [
                    Color.lerp(WowColors.panel, WowColors.ambient, 0.10)!,
                    WowColors.ink,
                  ],
                  stops: const [0, 0.7],
                ),
              ),
            ),
          if (mode == WowBackdropId.tonal)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(WowColors.panel, WowColors.ambient, 0.08)!, WowColors.ink],
                ),
              ),
            ),
          if (mode != WowBackdropId.flat)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.15,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  stops: const [0.55, 1],
                ),
              ),
            ),
          const IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: GrainPainter(), size: Size.infinite))),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class GrainPainter extends CustomPainter {
  const GrainPainter({this.seed = 7});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint();
    final count = (size.width * size.height / 520).clamp(900, 5200).toInt();
    for (var i = 0; i < count; i++) {
      paint.color = Colors.white.withValues(alpha: 0.012 + rnd.nextDouble() * 0.028);
      canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), 0.6 + rnd.nextDouble() * 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant GrainPainter oldDelegate) => oldDelegate.seed != seed;
}
