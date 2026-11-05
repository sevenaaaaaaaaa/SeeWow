import 'package:flutter/material.dart';

/// Cinema Editorial design tokens, shared by every platform.
class WowColors {
  static const ink = Color(0xFF07080B);
  static const shell = Color(0xFF0A0C11);
  static const panel = Color(0xFF10131A);
  static const line = Color(0x1AFFFFFF);
  static const text = Color(0xFFF7F7FA);
  static const muted = Color(0xFF9C9CA8);
  static const faint = Color(0xFF5E5F6B);
  static const accent = Color(0xFF8B7BFF);
  static const accent2 = Color(0xFF54C8FF);
  static const ambient = Color(0xFF8A6B3F);
}

class WowType {
  static const serif = 'SourceSerif4';
  static const mono = 'JetBrainsMono';

  /// Chinese needs its own serif voice: Songti on macOS, Noto Serif CJK elsewhere.
  static const serifFallback = <String>['Songti SC', 'STSong', 'Noto Serif CJK SC', 'Source Han Serif SC', 'Noto Serif SC'];

  static TextStyle display(
    double size,
    FontWeight weight, {
    double spacing = -0.8,
    Color color = WowColors.text,
    double height = 1.02,
  }) =>
      TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color,
      );

  static TextStyle monoLabel(double size, {FontWeight weight = FontWeight.w500, Color color = WowColors.muted, double spacing = 1.4}) =>
      TextStyle(fontFamily: mono, fontSize: size, fontWeight: weight, letterSpacing: spacing, color: color);

  static TextStyle body(double size, {Color color = WowColors.text, double height = 1.6}) =>
      TextStyle(fontSize: size, height: height, color: color, letterSpacing: 0.1);
}

class WowMotion {
  static const page = Cubic(0.22, 1, 0.36, 1);
  static const modal = Cubic(0.16, 1, 0.3, 1);
  static const snappy = Cubic(0.2, 0.8, 0.2, 1);
  /// Editorial entrance: quick out, long settle.
  static const entrance = Cubic(0.16, 1, 0.3, 1);
  static const pageDuration = Duration(milliseconds: 320);
  static const modalDuration = Duration(milliseconds: 380);
  static const enterDuration = Duration(milliseconds: 620);
}

class WowSpace {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
  static const xxl = 64.0;

  /// One fluid page gutter for every breakpoint.
  static double gutter(double width) => width < 760 ? 20 : (width < 1180 ? 34 : 56);
}