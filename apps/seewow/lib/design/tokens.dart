import 'package:flutter/material.dart';

import 'skin.dart';

/// Cinema Editorial design tokens, shared by every platform.
///
/// Every value here resolves through [WowSkin], so switching a preset in
/// Settings repaints the whole app without any screen knowing about presets.
class WowColors {
  static WowPalette get _p => WowSkin.I.palette;

  /// 当前皮肤是不是浅色。浅色皮肤下「叠白」等于把内容擦掉，凡是半透明的
  /// 文字、图标、描边都必须走 [fade] / [wash]，不能直接写 Colors.white。
  static bool get isLight => WowSkin.I.isLight;

  /// 半透明的文字与图标：深色皮肤叠白，浅色皮肤叠黑。
  ///
  /// 浅色分支把浓度乘 2.2，因为同样的透明度在亮底上看上去淡得多：深色皮肤里
  /// 0.30 的白是「次要信息」，换成白底后 0.30 的黑只有 1.1:1，等于消失。
  /// 2.2 是让 0.26 的 9px 标签也能过 4.5:1 的最小倍数。
  static Color fade(double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    if (isLight) {
      return const Color(0xFF000000)
          .withValues(alpha: (a * 2.2).clamp(0.0, 0.94));
    }
    return const Color(0xFFFFFFFF).withValues(alpha: a);
  }

  /// 半透明的面与描边：深色皮肤叠白，浅色皮肤叠黑。透明度保持原设计。
  static Color wash(double alpha) =>
      (isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF)).withValues(
        alpha: alpha.clamp(0.0, 1.0),
      );

  static Color get ink => _p.ink;
  static Color get shell => _p.shell;
  static Color get panel => _p.panel;
  static Color get line => WowSkin.I.spec.color('line');
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get faint => _p.faint;
  static Color get accent => WowSkin.I.accent;
  static Color get accent2 => WowSkin.I.accent2;
  static Color get onAccent => WowSkin.I.onAccent;
  static Color get success => WowSkin.I.spec.color('success');
  static Color get error => WowSkin.I.spec.color('error');
  static Color get ambient => _p.ambient;
}

class WowType {
  /// Display family for headings. Null means the platform default sans.
  static String? get serif => WowSkin.I.voice.display;

  /// Bundled mono stays fixed: metadata must look the same in every preset.
  static const mono = 'JetBrainsMono';

  static List<String> get serifFallback => [
    ...WowSkin.I.voice.fallback,
    'NotoSerifTibetan',
    'NotoSansArabic',
  ];

  /// Chinese needs its own voice; serif presets fall back to Songti, sans
  /// presets to PingFang.
  static List<String> get fallback => [
    ...WowSkin.I.voice.fallback,
    'NotoSerifTibetan',
    'NotoSansArabic',
  ];

  static TextStyle display(
    double size,
    FontWeight weight, {
    double spacing = -0.8,
    Color? color,
    double height = 1.02,
  }) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
    color: color ?? WowColors.text,
  );

  static TextStyle monoLabel(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
    double spacing = 1.4,
  }) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color ?? WowColors.muted,
  );

  static TextStyle body(double size, {Color? color, double height = 1.6}) =>
      TextStyle(
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        color: color ?? WowColors.text,
        letterSpacing: 0.1,
      );
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
  static double gutter(double width) =>
      width < 760 ? 20 : (width < 1180 ? 34 : 56);
}
