import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'skin_spec.dart';

/// One resolved surface set. Every screen reads these through [WowColors].
class WowPalette {
  const WowPalette({
    required this.ink,
    required this.shell,
    required this.panel,
    required this.ambient,
    required this.text,
    required this.muted,
    required this.faint,
  });

  final Color ink;
  final Color shell;
  final Color panel;
  final Color ambient;
  final Color text;
  final Color muted;
  final Color faint;
}

enum WowPaletteId { editorial, warm, ink, graphite }

enum WowAccentId { violet, ember, amber, cyan }

enum WowFontId { editorial, humanist, sans, geometric }

enum WowBackdropId { fog, vignette, tonal, flat }

enum WowPosterId { hue, neutral }

const Map<WowPaletteId, WowPalette> wowPalettes = {
  WowPaletteId.editorial: WowPalette(
    ink: Color(0xFF07080B),
    shell: Color(0xFF0A0C11),
    panel: Color(0xFF10131A),
    ambient: Color(0xFF8A6B3F),
    text: Color(0xFFF7F7FA),
    muted: Color(0xFF9C9CA8),
    faint: Color(0xFF5E5F6B),
  ),
  WowPaletteId.warm: WowPalette(
    ink: Color(0xFF12110F),
    shell: Color(0xFF161513),
    panel: Color(0xFF1C1A18),
    ambient: Color(0xFFC08A4A),
    text: Color(0xFFEFE9DE),
    muted: Color(0xFFAAA398),
    faint: Color(0xFF6E665B),
  ),
  WowPaletteId.ink: WowPalette(
    ink: Color(0xFF07080D),
    shell: Color(0xFF0B0D14),
    panel: Color(0xFF11141C),
    ambient: Color(0xFF2B4A6F),
    text: Color(0xFFEEF0F5),
    muted: Color(0xFFA3A9B8),
    faint: Color(0xFF6B7487),
  ),
  WowPaletteId.graphite: WowPalette(
    ink: Color(0xFF0F0F10),
    shell: Color(0xFF141415),
    panel: Color(0xFF19191B),
    ambient: Color(0xFF6B6B72),
    text: Color(0xFFEDEDED),
    muted: Color(0xFFA1A1A6),
    faint: Color(0xFF737373),
  ),
};

const Map<WowAccentId, Color> wowAccents = {
  WowAccentId.violet: Color(0xFF8B7BFF),
  WowAccentId.ember: Color(0xFFE0894A),
  WowAccentId.amber: Color(0xFFD8A24A),
  WowAccentId.cyan: Color(0xFF54C8FF),
};

/// Type voices. A null family means "the platform default sans", which is SF on
/// macOS, Segoe on Windows and Roboto on Android.
class WowVoice {
  const WowVoice({
    required this.display,
    required this.fallback,
    required this.isSerif,
  });
  final String? display;
  final List<String> fallback;
  final bool isSerif;
}

const Map<WowFontId, WowVoice> wowVoices = {
  WowFontId.editorial: WowVoice(
    display: 'SourceSerif4',
    fallback: [
      'Songti SC',
      'STSong',
      'Noto Serif CJK SC',
      'Source Han Serif SC',
      'Noto Serif SC',
    ],
    isSerif: true,
  ),
  WowFontId.humanist: WowVoice(
    display: 'Palatino',
    fallback: [
      'Palatino Linotype',
      'Songti SC',
      'Noto Serif CJK SC',
      'Georgia',
      'serif',
    ],
    isSerif: true,
  ),
  WowFontId.sans: WowVoice(
    display: null,
    fallback: [
      'PingFang SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    isSerif: false,
  ),
  WowFontId.geometric: WowVoice(
    display: 'Avenir Next',
    fallback: [
      'Avenir',
      'PingFang SC',
      'Noto Sans CJK SC',
      'Helvetica Neue',
      'sans-serif',
    ],
    isSerif: false,
  ),
};

/// Global, persisted look-and-feel. Widgets listen through [WowColors] getters,
/// so a single notifyListeners rebuilds every screen with the new values.
class WowSkin extends ChangeNotifier {
  WowSkin._() {
    _custom = builtInSkins.first;
  }
  static final WowSkin I = WowSkin._();

  WowPaletteId paletteId = WowPaletteId.graphite;
  WowAccentId accentId = WowAccentId.violet;
  WowFontId fontId = WowFontId.sans;
  WowBackdropId backdropId = WowBackdropId.flat;
  WowPosterId posterId = WowPosterId.neutral;

  SkinSpec? _custom;
  String preset = '曜黑';
  final List<SkinSpec> installed = [];
  SkinSpec get spec => _custom ?? builtInSkins.first;
  bool get isLight => spec.light;
  bool get isGlass => spec.glass;
  WowPalette get palette => _custom == null
      ? wowPalettes[paletteId]!
      : WowPalette(
          ink: spec.color('background'),
          shell: spec.color('shell'),
          panel: spec.color('panel'),
          ambient: spec.color('ambient'),
          text: spec.color('text'),
          muted: spec.color('muted'),
          faint: spec.color('faint'),
        );
  void use(SkinSpec value, {bool install = false}) {
    _custom = value;
    preset = value.name;
    fontId = WowFontId.values.firstWhere((v) => v.name == value.font);
    if (install) {
      installed.removeWhere((s) => s.name == value.name);
      installed.add(value);
      if (installed.length > 40) installed.removeAt(0);
    }
    notifyListeners();
    save();
  }

  void removeInstalled(String name) {
    installed.removeWhere((s) => s.name == name);
    notifyListeners();
    save();
  }

  WowVoice get voice => wowVoices[fontId]!;

  Color get accent => _custom?.color('accent') ?? wowAccents[accentId]!;

  /// Violet keeps its companion cyan for the retro-compatible logo; every other
  /// accent is a single solid fill.
  Color get accent2 => _custom != null
      ? accent
      : (accentId == WowAccentId.violet ? const Color(0xFF54C8FF) : accent);

  Color get onAccent =>
      _custom?.onAccent ??
      (accent.computeLuminance() > 0.18
          ? const Color(0xFF12100C)
          : const Color(0xFFFDFBF7));

  bool get legacyLogo => accentId == WowAccentId.violet;

  void apply({
    WowPaletteId? palette,
    WowAccentId? accent,
    WowFontId? font,
    WowBackdropId? backdrop,
    WowPosterId? poster,
  }) {
    _custom = null;
    if (palette != null) paletteId = palette;
    if (accent != null) accentId = accent;
    if (font != null) fontId = font;
    if (backdrop != null) backdropId = backdrop;
    if (poster != null) posterId = poster;
    notifyListeners();
    save();
  }

  void reset() => use(builtInSkins.first);

  // ---- persistence -------------------------------------------------------
  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/SeeWow');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/skin.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        reset();
        return;
      }
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (raw['version'] != 2) {
        reset();
        return;
      }
      final saved = raw['skin'];
      if (saved is Map<String, dynamic>) _custom = SkinSpec.fromJson(saved);
      preset = spec.name;
      installed.clear();
      for (final value in (raw['installed'] as List? ?? []).take(40)) {
        try {
          installed.add(
            SkinSpec.fromJson(Map<String, dynamic>.from(value as Map)),
          );
        } catch (_) {
          /* Skip an invalid imported entry without losing the active skin. */
        }
      }
      paletteId = _pick(WowPaletteId.values, raw['palette'], paletteId);
      accentId = _pick(WowAccentId.values, raw['accent'], accentId);
      fontId = WowFontId.values.firstWhere((v) => v.name == spec.font);
      backdropId = _pick(WowBackdropId.values, raw['backdrop'], backdropId);
      posterId = _pick(WowPosterId.values, raw['poster'], posterId);
      notifyListeners();
    } catch (e) {
      debugPrint('skin load failed: $e');
    }
  }

  Future<void> _writes = Future.value();
  Future<void> save() {
    final snapshot = {
      'version': 2,
      'skin': spec.toJson(),
      'installed': installed.map((s) => s.toJson()).toList(),
      'palette': paletteId.name,
      'accent': accentId.name,
      'font': fontId.name,
      'backdrop': backdropId.name,
      'poster': posterId.name,
    };
    _writes = _writes.then((_) async {
      try {
        final file = await _file();
        await file.writeAsString(jsonEncode(snapshot));
      } catch (e) {
        debugPrint('skin save failed: $e');
      }
    });
    return _writes;
  }

  static T _pick<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

String wowPaletteLabel(WowPaletteId id) => switch (id) {
  WowPaletteId.editorial => '古铜',
  WowPaletteId.warm => '暖墨',
  WowPaletteId.ink => '墨蓝',
  WowPaletteId.graphite => '石墨',
};

String wowAccentLabel(WowAccentId id) => switch (id) {
  WowAccentId.violet => '紫',
  WowAccentId.ember => '余烬橙',
  WowAccentId.amber => '琥珀',
  WowAccentId.cyan => '冷青',
};

String wowFontLabel(WowFontId id) => switch (id) {
  WowFontId.editorial => '宋衬线',
  WowFontId.humanist => '人文衬线',
  WowFontId.sans => '无衬线',
  WowFontId.geometric => '几何',
};

String wowBackdropLabel(WowBackdropId id) => switch (id) {
  WowBackdropId.fog => '彩色雾',
  WowBackdropId.vignette => '中性暗角',
  WowBackdropId.tonal => '中性微渐变',
  WowBackdropId.flat => '纯平',
};

String wowPosterLabel(WowPosterId id) => switch (id) {
  WowPosterId.hue => '哈希色相',
  WowPosterId.neutral => '中性',
};
