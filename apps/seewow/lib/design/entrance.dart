import 'package:flutter/material.dart';
import 'tokens.dart';

/// Staggered editorial entrance: fade + rise, running once per subtree.
class RiseIn extends StatefulWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.rise = 14,
    this.duration = WowMotion.enterDuration,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final double rise;
  final Duration duration;
  final bool enabled;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: WowMotion.entrance);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, widget.rise * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Cursor-magnetic wrapper: the target leans toward the pointer, then settles back.
class Magnetic extends StatefulWidget {
  const Magnetic({super.key, required this.child, this.strength = 4, this.enabled = true});
  final Widget child;
  final double strength;
  final bool enabled;

  @override
  State<Magnetic> createState() => _MagneticState();
}

class _MagneticState extends State<Magnetic> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        if (!widget.enabled) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(e.position);
        final dx = (local.dx / box.size.width - 0.5) * 2;
        final dy = (local.dy / box.size.height - 0.5) * 2;
        setState(() => _offset = Offset(dx * widget.strength, dy * widget.strength));
      },
      onExit: (_) => setState(() => _offset = Offset.zero),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: WowMotion.snappy,
        transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
        child: widget.child,
      ),
    );
  }
}
