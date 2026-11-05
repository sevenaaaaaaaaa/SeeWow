import 'package:flutter/material.dart';

/// Projection gate: a hairline frame with cut corners.
/// Reads as a film frame rather than a UI card border.
class GatePainter extends CustomPainter {
  const GatePainter({this.inset = 22, this.color = const Color(0x1FFFFFFF)});
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const tick = 16.0;
    final l = inset, t = inset, r = size.width - inset, b = size.height - inset;
    canvas.drawLine(Offset(l, t), Offset(l + tick, t), p);
    canvas.drawLine(Offset(l, t), Offset(l, t + tick), p);
    canvas.drawLine(Offset(r, t), Offset(r - tick, t), p);
    canvas.drawLine(Offset(r, t), Offset(r, t + tick), p);
    canvas.drawLine(Offset(l, b), Offset(l + tick, b), p);
    canvas.drawLine(Offset(l, b), Offset(l, b - tick), p);
    canvas.drawLine(Offset(r, b), Offset(r - tick, b), p);
    canvas.drawLine(Offset(r, b), Offset(r, b - tick), p);
  }

  @override
  bool shouldRepaint(covariant GatePainter oldDelegate) => oldDelegate.inset != inset || oldDelegate.color != color;
}

class GateFrame extends StatelessWidget {
  const GateFrame({super.key, this.inset = 22, this.opacity = 0.12});
  final double inset;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: GatePainter(inset: inset, color: Colors.white.withValues(alpha: opacity))),
    );
  }
}
