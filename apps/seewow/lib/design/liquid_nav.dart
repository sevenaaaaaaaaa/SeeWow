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
    final shape = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            WowColors.accent.withValues(alpha: (strength * 1.12).clamp(0.0, 1.0)),
            WowColors.accent.withValues(alpha: strength * .46),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: .22),
          width: .9,
        ),
        boxShadow: [
          BoxShadow(
            color: WowColors.accent.withValues(alpha: .18),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
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
                      Colors.white.withValues(alpha: .30),
                      Colors.white.withValues(alpha: 0),
                    ],
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

class _Seat extends StatelessWidget {
  const _Seat({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

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
            style: TextStyle(
              fontSize: 9.5,
              height: 1,
              letterSpacing: .1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
            child: Text(tab.label, maxLines: 1),
          ),
        ],
      ),
    );
  }
}
