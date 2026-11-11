import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

class SkinCanvas extends StatelessWidget {
  const SkinCanvas({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WowColors.ink,
      gradient: WowSkin.I.isGlass
          ? RadialGradient(
              center: const Alignment(.8, -.9),
              radius: 1.7,
              colors: [
                Color.alphaBlend(
                  WowColors.ambient.withValues(alpha: .35),
                  WowColors.ink,
                ),
                WowColors.ink,
              ],
            )
          : null,
    ),
    child: child,
  );
}

/// Blur is clipped to a surface; artwork and long media grids stay unfiltered.
class SkinSurface extends StatelessWidget {
  const SkinSurface({super.key, required this.child, this.radius, this.color});
  final Widget child;
  final double? radius;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final skin = WowSkin.I;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius ?? skin.spec.radius),
      side: BorderSide(color: WowColors.line),
    );
    Widget surface = Material(
      color: (color ?? WowColors.panel).withValues(
        alpha: skin.isGlass ? skin.spec.opacity : 1,
      ),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (skin.isGlass && !MediaQuery.disableAnimationsOf(context)) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? skin.spec.radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: skin.spec.blur,
            sigmaY: skin.spec.blur,
          ),
          child: surface,
        ),
      );
    }
    return surface;
  }
}
