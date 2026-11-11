import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

ThemeData buildWowTheme() => ThemeData(
  useMaterial3: true,
  visualDensity: WowSkin.I.spec.compact
      ? VisualDensity.compact
      : VisualDensity.standard,
  brightness: WowSkin.I.isLight ? Brightness.light : Brightness.dark,
  scaffoldBackgroundColor: WowColors.ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: WowColors.accent,
    brightness: WowSkin.I.isLight ? Brightness.light : Brightness.dark,
    primary: WowColors.accent,
    onPrimary: WowColors.onAccent,
    secondary: WowColors.accent,
    surface: WowColors.panel,
    onSurface: WowColors.text,
    onSurfaceVariant: WowColors.muted,
    error: WowColors.error,
    outline: WowColors.line,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WowSkin.I.spec.radius.clamp(0, 12)),
      ),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: WowColors.text,
      minimumSize: const Size(44, 44),
      side: BorderSide(color: WowColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WowSkin.I.spec.radius.clamp(0, 12)),
      ),
      textStyle: const TextStyle(fontSize: 12),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: WowColors.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(WowSkin.I.spec.radius.clamp(0, 12)),
      borderSide: BorderSide(color: WowColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(WowSkin.I.spec.radius.clamp(0, 12)),
      borderSide: BorderSide(color: WowColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(WowSkin.I.spec.radius.clamp(0, 12)),
      borderSide: BorderSide(color: WowColors.accent),
    ),
    hintStyle: TextStyle(color: WowColors.muted, fontSize: 12),
  ),
  chipTheme: ChipThemeData(
    side: BorderSide(color: WowColors.line),
    backgroundColor: WowColors.panel,
    selectedColor: WowColors.accent.withValues(alpha: .15),
    labelStyle: TextStyle(fontSize: 12, color: WowColors.text),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: WowColors.shell,
    indicatorColor: WowColors.accent.withValues(alpha: .15),
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 10, color: WowColors.text),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: WowColors.panel,
    surfaceTintColor: Colors.transparent,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: WowColors.panel,
    surfaceTintColor: Colors.transparent,
  ),
  dividerColor: WowColors.line,
  canvasColor: WowColors.panel,

  splashFactory: InkRipple.splashFactory,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  fontFamily: WowType.serif,
  fontFamilyFallback: WowType.fallback,
  progressIndicatorTheme: ProgressIndicatorThemeData(
    linearTrackColor: WowColors.line,
    color: WowColors.accent,
  ),
);
