import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid_glass.dart';
import 'skin.dart';
import 'tokens.dart';

/// One seat in the tab bar.
class LiquidTab {
  const LiquidTab({required this.label, required this.icon, this.activeIcon});
  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

/// The floating Liquid Glass tab bar.
///
/// The selection is one pane of glass that travels between seats: it stretches
/// while it moves and settles back when it lands, which is what makes the bar
/// read as liquid rather than as five buttons with a highlight. Everything the
/// material does here is opt-in and follows the system reduce-motion setting.
class LiquidTabBar extends StatefulWidget {
  const LiquidTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
    this.height = 62,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 0),
  });

  final List<LiquidTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final double height;
  final EdgeInsetsGeometry margin;

  @override
  State<LiquidTabBar> createState() => _LiquidTabBarState();
}

class _LiquidTabBarState extends State<LiquidTabBar> {
  late double _from = widget.index.toDouble();

  @override
  void didUpdateWidget(LiquidTabBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _from = old.index.toDouble();
  }

  void _tap(int i) {
    if (i == widget.index) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      HapticFeedback.selectionClick();
    }
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final skin = WowSkin.I;
    final tint = skin.isGlass ? WowColors.shell : WowColors.panel;
    return Padding(
      padding: widget.margin,
      child: SizedBox(
        height: widget.height,
        child: GlassSheen(
          radius: 28,
          strength: .12,
          enabled: !reduce,
          play: widget.index,
          child: Stack(
            children: [
              Positioned.fill(
                child: LiquidGlass(
                  radius: 28,
                  tint: tint,
                  opacity: skin.isGlass ? .76 : .97,
                  edge: .34,
                  refraction: .85,
                  lifted: false,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final seat = c.maxWidth / widget.tabs.length;
                    return TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: _from,
                        end: widget.index.toDouble(),
                      ),
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 430),
                      curve: WowMotion.page,
                      builder: (context, t, _) {
                        final frac = (t - t.roundToDouble()).abs();
                        final stretch = reduce
                            ? 0.0
                            : math.sin(frac * math.pi) * seat * .18;
                        return Stack(
                          children: [
                            Positioned(
                              left: t * seat + 6,
                              top: 7,
                              width: seat - 12 + stretch,
                              height: widget.height - 14,
                              child: _SelectionPane(strength: .20),
                            ),
                            for (var i = 0; i < widget.tabs.length; i++)
                              Positioned(
                                left: i * seat,
                                top: 0,
                                width: seat,
                                height: widget.height,
                                child: _Seat(
                                  tab: widget.tabs[i],
                                  selected: i == widget.index,
                                  onTap: () => _tap(i),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionPane extends StatelessWidget {
  const _SelectionPane({required this.strength});
  final double strength;

  @override
  Widget build(BuildContext context) {
    // The selection is the same material as the bar it sits in, tinted — not a
    // separate painted pill. Concentric on purpose: the bar is 28, the inset is
    // 6, so the pill is 22. Two panes that both pick their own radius look
    // wrong at every size except one.
    final radius = GlassTokens.concentric(28, 6);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: WowColors.accent.withValues(alpha: .16),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      child: LiquidGlass(
        radius: radius,
        tint: WowColors.accent,
        opacity: strength,
        edge: .30,
        refraction: .55,
        lifted: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              // Specular band: the pill is lit from above, like a bead of glass.
              Positioned(
                left: 5,
                right: 5,
                top: 1.5,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: .26),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.tab, required this.selected, required this.onTap});

  final LiquidTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 260);
    final color = selected
        ? WowColors.text
        : WowColors.muted.withValues(alpha: .88);
    return PressableLens(
      radius: 20,
      onTap: onTap,
      selected: selected,
      semanticLabel: tab.label,
      // 座位是定宽定高的 Positioned，但 PressableLens 里的 Stack 会把
      // 非 Positioned 的子节点按 topStart 摆、并让它们自己缩到内容宽——
      // 结果图标和文字贴着座位左边，视觉上整排 tab 都向左错位。
      // 撑满座位再居中，才是「每个座位一格、内容在格里」。
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: dur,
              curve: WowMotion.page,
              scale: selected ? 1.06 : 1,
              child: Icon(
                selected ? (tab.activeIcon ?? tab.icon) : tab.icon,
                size: 21,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: dur,
              curve: WowMotion.page,
              // The label follows the skin's voice instead of whatever the
              // ambient DefaultTextStyle happens to be: a serif skin gets a
              // serif label, a sans skin gets a sans one, and neither depends on
              // a fallback the platform may not have.
              style: TextStyle(
                fontSize: 9.5,
                height: 1,
                letterSpacing: .1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                fontFamily: WowSkin.I.voice.display,
                fontFamilyFallback: WowSkin.I.voice.fallback,
              ),
              child: Text(tab.label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
