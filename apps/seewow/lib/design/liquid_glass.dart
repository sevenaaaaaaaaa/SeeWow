import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

/// Liquid Glass — a translucent pane that bends what sits behind it.
///
/// Three layers make the material read as glass instead of a flat card: a real
/// backdrop blur, a lit tint (bright at the top-left, dense at the bottom), and
/// a hairline edge whose strength runs from bright at the top to nearly gone at
/// the bottom. Nothing here animates on its own, so a screen full of panes
/// stays cheap; motion lives in [GlassSheen] and [PressableLens], which a
/// caller opts into.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 22,
    this.tint,
    this.opacity,
    this.blur,
    this.padding,
    this.edge = .22,
    this.lifted = true,
    this.edgeVisible = true,
  });

  final Widget child;
  final double radius;
  final Color? tint;
  final double? opacity;
  final double? blur;
  final EdgeInsetsGeometry? padding;

  /// Hairline strength. About 0.28 reads as a lifted sheet, 0.14 as a whisper.
  final double edge;

  /// Outer shadow; off for panes that sit inside another pane.
  final bool lifted;

  /// Hairline plus specular band. Off for surfaces that must read flat.
  final bool edgeVisible;

  @override
  Widget build(BuildContext context) {
    final skin = WowSkin.I;
    final shape = BorderRadius.circular(radius);
    final base = tint ?? WowColors.panel;
    final alpha = (opacity ?? (skin.isGlass ? skin.spec.opacity : .94)).clamp(
      0.0,
      1.0,
    );
    final sigma = (blur ?? (skin.isGlass ? skin.spec.blur : 0)).clamp(0.0, 80.0);

    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: skin.isGlass ? null : base.withValues(alpha: alpha),
        gradient: skin.isGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: .07),
                    base,
                  ).withValues(alpha: alpha),
                  base.withValues(alpha: (alpha * .90).clamp(0.0, 1.0)),
                ],
              )
            : null,
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    Widget surface = ClipRRect(
      borderRadius: shape,
      child: sigma > 0
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: pane,
            )
          : pane,
    );

    if (edgeVisible) {
      surface = Stack(
        fit: StackFit.passthrough,
        children: [
          surface,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: shape,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: edge * .34),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EdgeSheen(radius: radius, strength: edge),
              ),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .42),
                  blurRadius: radius * 1.5,
                  offset: Offset(0, radius * .34),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: surface,
    );
  }
}

/// The bright rim of a pane: a gradient stroke plus a soft specular band that
/// only covers the top third. Painted, not layered, so it costs one draw call.
class _EdgeSheen extends CustomPainter {
  const _EdgeSheen({required this.radius, required this.strength});

  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          Colors.white.withValues(alpha: strength),
          Colors.white.withValues(alpha: strength * .16),
          Colors.white.withValues(alpha: strength * .48),
        ],
        const [0, .58, 1],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.6), Radius.circular(radius)),
      stroke,
    );

    final band = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        Offset(rect.center.dx, rect.top + rect.height * .5),
        [
          Colors.white.withValues(alpha: strength * .46),
          Colors.white.withValues(alpha: 0),
        ],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.7), Radius.circular(radius)),
      band,
    );
  }

  @override
  bool shouldRepaint(_EdgeSheen old) =>
      old.radius != radius || old.strength != strength;
}

/// A specular band that slides across a pane once, the way light moves over
/// wet glass when the surface tilts.
///
/// It is a one-shot, not a loop: [play] advances and the band travels, then the
/// surface rests. A bar that shimmers forever is decoration, and a repeating
/// ticker is also something no widget test can ever settle.
class GlassSheen extends StatefulWidget {
  const GlassSheen({
    super.key,
    required this.child,
    this.radius = 24,
    this.duration = const Duration(milliseconds: 900),
    this.strength = .085,
    this.enabled = true,
    this.play = 0,
  });

  final Widget child;
  final double radius;
  final Duration duration;
  final double strength;
  final bool enabled;

  /// Change this to sweep again. The first build rests instead of sweeping.
  final int play;

  @override
  State<GlassSheen> createState() => _GlassSheenState();
}

class _GlassSheenState extends State<GlassSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(GlassSheen old) {
    super.didUpdateWidget(old);
    if (widget.play != old.play) {
      final reduce = MediaQuery.disableAnimationsOf(context);
      if (widget.enabled && !reduce) {
        _c.forward(from: 0);
      } else {
        _c.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _c.value >= 1
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _SheenPainter(
                          t: _c.value,
                          strength: widget.strength,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter({required this.t, required this.strength});

  final double t;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final travel = size.width * 1.6 + size.height;
    final x = -size.height + travel * t;
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        Offset(x, 0),
        Offset(x + size.height * .9, size.height * .5),
        [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: strength),
          Colors.white.withValues(alpha: 0),
        ],
        const [0, .5, 1],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter old) =>
      old.t != t || old.strength != strength;
}

/// A lens that follows a press: the pane brightens under the finger, squashes a
/// little, then settles back.
class PressableLens extends StatefulWidget {
  const PressableLens({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 18,
    this.semanticLabel,
    this.selected = false,
    this.enabled = true,
    this.scale = .965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final String? semanticLabel;
  final bool selected;
  final bool enabled;
  final double scale;

  @override
  State<PressableLens> createState() => _PressableLensState();
}

class _PressableLensState extends State<PressableLens> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final live = widget.enabled && widget.onTap != null;
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 190);
    return Semantics(
      button: true,
      enabled: live,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: live ? (_) => setState(() => _down = true) : null,
          onTapCancel: live ? () => setState(() => _down = false) : null,
          onTapUp: live ? (_) => setState(() => _down = false) : null,
          onTap: live ? widget.onTap : null,
          child: AnimatedScale(
            duration: dur,
            curve: WowMotion.snappy,
            scale: _down && live ? widget.scale : 1,
            child: AnimatedContainer(
              duration: dur,
              curve: WowMotion.snappy,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                color: _down
                    ? Colors.white.withValues(alpha: .10)
                    : Colors.transparent,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A page that opens the way a pane of glass slides over another one: the new
/// screen fades up from slightly smaller while the old one dims behind it.
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required this.builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondary, child) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: WowMotion.page,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: .972, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );

  final WidgetBuilder builder;
}
