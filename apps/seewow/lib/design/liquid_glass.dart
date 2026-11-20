import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

/// Whether the glass is the dark material or the light one.
///
/// Apple's Liquid Glass is not one material: it is a *system* material that
/// adapts to what it sits on. A dark pane over a dark plate needs a bright
/// rim to exist at all, while a light pane needs a dark hairline instead —
/// drawing a white rim on white glass is what makes fake glass look like a
/// sticker. [GlassTone.auto] resolves from the active skin, then from the
/// platform, so a screen never has to pass the tone itself.
enum GlassTone { auto, dark, light }

/// The numbers that make glass read as glass, in one place.
class GlassTokens {
  const GlassTokens._();

  /// Visual thickness of the material, in logical pixels. This is the offset
  /// between the outer specular rim and the inner shadow rim.
  static const double thickness = 1.4;

  /// Minimum corner radius. Below 8 a glass pane reads as a rounded box
  /// instead of a formed piece of material.
  static const double minRadius = 8;

  /// Apple's concentric rule: a pane nested inside another pane is not given
  /// its own radius, it is given *the parent's radius minus the inset*. Two
  /// panes that both pick 20 look wrong at every size except one.
  static double concentric(double outerRadius, double inset) =>
      math.max(minRadius, outerRadius - inset);

  /// Minimum touch target on a phone. iOS HIG asks for 44; a glass button that
  /// is visually 32 still reserves 44.
  static const double touchTarget = 44;

  static GlassTone resolve(BuildContext context, GlassTone tone) {
    if (tone != GlassTone.auto) return tone;
    return WowSkin.I.spec.light ? GlassTone.light : GlassTone.dark;
  }
}

/// Liquid Glass — a translucent pane that bends what sits behind it.
///
/// What actually makes this read as material rather than as a translucent
/// card, in the order each layer contributes:
///
/// 1. **Backdrop blur** — the pane samples what is behind it instead of
///    pretending. Skipped entirely when the skin is flat or when the system
///    asks for reduced transparency, because a blur the user did not ask for
///    is the most expensive thing on the screen.
/// 2. **Tonal body** — a gradient, never a flat fill: the pressed/darker end
///    of the gradient is what the eye reads as thickness.
/// 3. **Specular rim** — a 1 px stroke that is bright at the lit corner and
///    goes to nearly nothing on the shadow side.
/// 4. **Inner shadow rim** — the dark hairline *inside* the bright one. This
///    is the detail that separates glass from a border: light on the outside
///    edge, shade on the inside edge.
/// 5. **Contact shadow** — the pane is lit from above, so it casts down.
///
/// Nothing here animates on its own, so a screen full of panes stays cheap;
/// motion lives in [GlassSheen] and [PressableLens], which a caller opts into.
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
    this.tone = GlassTone.auto,
    this.refraction = .6,
    this.concentric,
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

  final GlassTone tone;

  /// How strongly the rim bends light, 0 to 1. Zero keeps a plain hairline;
  /// one adds a full inner shade and a bounce line at the bottom.
  final double refraction;

  /// Concentric corner: the outer radius of the pane this one sits inside,
  /// plus the inset. Wins over [radius] when given.
  final ({double outer, double inset})? concentric;

  @override
  Widget build(BuildContext context) {
    final skin = WowSkin.I;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final tonal = GlassTokens.resolve(context, tone);
    final light = tonal == GlassTone.light;
    final effectiveRadius = concentric == null
        ? radius
        : GlassTokens.concentric(concentric!.outer, concentric!.inset);
    final shape = BorderRadius.circular(effectiveRadius);
    final base = tint ?? WowColors.panel;
    final alpha = (opacity ?? (skin.isGlass ? skin.spec.opacity : .94)).clamp(
      0.0,
      1.0,
    );
    final sigma = highContrast
        ? 0.0
        : (blur ?? (skin.isGlass ? skin.spec.blur : 0)).clamp(0.0, 80.0);

    // A flat or high-contrast pane is opaque on purpose: reduced transparency
    // is a preference, not a suggestion.
    final translucent = sigma > 0 && alpha < 1;

    final body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: .72),
                    base,
                  ).withValues(alpha: alpha),
                  base.withValues(alpha: (alpha * .96).clamp(0.0, 1.0)),
                ]
              : [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: .075),
                    base,
                  ).withValues(alpha: alpha),
                  base.withValues(alpha: (alpha * .90).clamp(0.0, 1.0)),
                ],
        ),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    Widget surface = ClipRRect(
      borderRadius: shape,
      child: translucent
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: body,
            )
          : body,
    );

    if (edgeVisible) {
      surface = Stack(
        fit: StackFit.passthrough,
        children: [
          surface,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassEdge(
                  radius: effectiveRadius,
                  strength: edge,
                  light: light,
                  refraction: refraction,
                  translucent: translucent,
                ),
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
                  color: Colors.black.withValues(alpha: light ? .16 : .42),
                  blurRadius: effectiveRadius * 1.5,
                  offset: Offset(0, effectiveRadius * .34),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? .06 : .18),
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

/// The rim: light on the outside edge, shade on the inside edge, and a bounce
/// line along the bottom. Painted rather than layered, so the whole edge costs
/// three draw calls however large the pane is.
class _GlassEdge extends CustomPainter {
  const _GlassEdge({
    required this.radius,
    required this.strength,
    required this.light,
    required this.refraction,
    required this.translucent,
  });

  final double radius;
  final double strength;
  final bool light;
  final double refraction;
  final bool translucent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = Radius.circular(math.max(2, radius - .7));

    // Outer specular rim. On light glass a pure white rim disappears, so the
    // light material uses a white highlight *and* a dark hairline below it.
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        light
            ? [
                Colors.white.withValues(alpha: .95),
                Colors.black.withValues(alpha: .10),
                Colors.black.withValues(alpha: .05),
              ]
            : [
                Colors.white.withValues(alpha: strength),
                Colors.white.withValues(alpha: strength * .14),
                Colors.white.withValues(alpha: strength * .44),
              ],
        const [0, .55, 1],
      );
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(.6), r), outer);

    if (refraction <= 0) return;

    // Inner shade: the material has thickness, so the inside of the edge is
    // darker than the surface. This is the single detail that separates glass
    // from a card with a border.
    final inner = rect.deflate(GlassTokens.thickness + .9);
    final innerR = Radius.circular(math.max(2, radius - glassInset));
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = ui.Gradient.linear(
        inner.bottomLeft,
        inner.topRight,
        [
          Colors.black.withValues(alpha: .16 * refraction),
          const Color(0x00000000),
          Colors.white.withValues(alpha: .16 * refraction),
        ],
        const [0, .5, 1],
      );
    canvas.drawRRect(RRect.fromRectAndRadius(inner, innerR), shade);

    if (translucent) {
      // Internal reflection: a soft band just inside the rim, brightest where
      // light entered.
      final band = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          Offset(rect.center.dx, rect.bottom),
          [
            Colors.white.withValues(alpha: .16 * refraction),
            const Color(0x00000000),
          ],
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(4), Radius.circular(radius - 4)),
        band,
      );
    }
  }

  double get glassInset => GlassTokens.thickness + .9;

  @override
  bool shouldRepaint(_GlassEdge old) =>
      old.radius != radius ||
      old.strength != strength ||
      old.light != light ||
      old.refraction != refraction ||
      old.translucent != translucent;
}

/// A glass pill button: the one button shape this app uses for secondary
/// actions. It always reserves 44 px of height, even when it looks 32, because
/// a control that is hard to hit is a control that does not exist on a phone.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.prominent = false,
    this.dense = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool prominent;
  final bool dense;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final height = dense ? 36.0 : GlassTokens.touchTarget;
    final enabled = onTap != null;
    final fg = prominent ? WowColors.onAccent : WowColors.text;
    final content = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 15 : 17, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: WowType.body(
                dense ? 12.5 : 13.5,
                color: fg,
              ).copyWith(fontWeight: FontWeight.w600, letterSpacing: .1),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      child: PressableLens(
        onTap: onTap,
        enabled: enabled,
        radius: height / 2,
        child: prominent
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: WowColors.accent,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
                child: content,
              )
            : LiquidGlass(
                radius: height / 2,
                edge: .30,
                lifted: false,
                padding: EdgeInsets.zero,
                child: content,
              ),
      ),
    );
  }
}

/// A bottom sheet made of glass: grabber, title, content.
///
/// The grabber is not decoration — it is the affordance that says "this can be
/// pulled down", which is the fastest way out of a sheet on a phone.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: LiquidGlass(
        radius: 30,
        edge: .32,
        lifted: false,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: WowColors.muted.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: WowType.display(
                      22,
                      FontWeight.w500,
                      spacing: -.4,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle!,
                        style: WowType.body(12, color: WowColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Opens a glass sheet. The scrim is darker than Material's default so the
/// material reads as lit from the app, not from the system.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .58),
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: builder(context),
    ),
  );
}

/// A specular band that slides across a pane once, the way light moves over
/// wet glass when the surface tilts.
///
/// It is a one-shot, not a loop: play advances and the band travels, then the
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
/// little, then settles back. It also carries keyboard activation, so a glass
/// control is reachable without a pointer.
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
  bool _focused = false;

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
      child: FocusableActionDetector(
        enabled: live,
        mouseCursor: live ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
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
            if (_focused)
              Positioned(
                left: -3,
                top: -3,
                right: -3,
                bottom: -3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius + 3),
                      border: Border.all(
                        color: WowColors.accent.withValues(alpha: .9),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A screen that opens the way one pane of glass slides over another: it
/// fades up from slightly smaller and further down, then settles. The scale is
/// small on purpose — 0.95 is the difference between a sheet of material and a
/// pop-up toy.
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required this.builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondary, child) {
          if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: const Cubic(.16, 1, .3, 1),
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .018),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: .958, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );

  final WidgetBuilder builder;
}

/// A round glass icon button. One shape for every secondary action that has
/// an icon and no room for a label; 44 px of hit area whatever [size] it is
/// drawn at.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.label,
    this.selected = false,
    this.size = GlassTokens.touchTarget,
    this.iconSize = 19,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? label;
  final bool selected;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label ?? '',
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        enabled: onTap != null,
        child: PressableLens(
          radius: size / 2,
          onTap: onTap,
          enabled: onTap != null,
          selected: selected,
          child: SizedBox(
            width: size,
            height: size,
            child: LiquidGlass(
              radius: size / 2,
              edge: .30,
              lifted: false,
              tint: selected ? WowColors.accent : null,
              opacity: selected ? .20 : null,
              child: Icon(
                icon,
                size: iconSize,
                color: selected ? WowColors.accent : WowColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
