import 'dart:convert';

import 'package:flutter/material.dart';

/// Portable, declarative skins. No code, remote assets or filesystem references.
class SkinSpec {
  SkinSpec._(this.data);
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  String get author => data['author'] as String;
  String get description => data['description'] as String;
  bool get light => data['mode'] == 'light';
  bool get glass => data['material'] == 'glass';
  String get font => data['font'] as String;
  double get radius => (data['radius'] as num).toDouble();
  double get posterRadius => (data['posterRadius'] as num).toDouble();
  double get blur => (data['blur'] as num).toDouble();
  double get opacity => (data['opacity'] as num).toDouble();
  bool get compact => data['density'] == 'compact';
  Color color(String role) =>
      parseColor((data['colors'] as Map)[role] as String);
  Color get onAccent =>
      contrast(Colors.white, color('accent')) >
          contrast(const Color(0xFF101114), color('accent'))
      ? Colors.white
      : const Color(0xFF101114);
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  String encode() => const JsonEncoder.withIndent('  ').convert(data);
  SkinSpec edit(Map<String, dynamic> changes) =>
      SkinSpec.fromJson({...toJson(), ...changes});

  static const roles = [
    'background',
    'shell',
    'panel',
    'text',
    'muted',
    'faint',
    'accent',
    'line',
    'ambient',
    'success',
    'error',
  ];
  static Color parseColor(String value) {
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw const FormatException('颜色需要使用 #RRGGBB 格式');
    }
    return Color(int.parse('FF${value.substring(1)}', radix: 16));
  }

  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
  }

  factory SkinSpec.fromJson(Map<String, dynamic> raw) {
    const keys = [
      'schemaVersion',
      'name',
      'author',
      'description',
      'mode',
      'material',
      'font',
      'radius',
      'posterRadius',
      'blur',
      'opacity',
      'density',
      'colors',
    ];
    if (raw.keys.any((k) => !keys.contains(k)))
      throw const FormatException('皮肤包含不支持的字段');
    if (raw['schemaVersion'] != 1)
      throw const FormatException('仅支持 schemaVersion: 1');
    final d = <String, dynamic>{
      'author': '社区作者',
      'description': '',
      'font': 'sans',
      'radius': 16,
      'posterRadius': 10,
      'blur': 24,
      'opacity': .78,
      'density': 'comfortable',
      ...raw,
    };
    for (final key in ['name', 'author', 'description']) {
      if (d[key] is! String ||
          (d[key] as String).length > (key == 'description' ? 500 : 60)) {
        throw FormatException('$key 文本格式无效');
      }
    }
    if ((d['name'] as String).trim().isEmpty)
      throw const FormatException('请填写皮肤名称');
    for (final entry in {
      'mode': ['light', 'dark'],
      'material': ['flat', 'glass'],
      'font': ['sans', 'editorial', 'humanist', 'geometric'],
      'density': ['comfortable', 'compact'],
    }.entries) {
      if (!entry.value.contains(d[entry.key]))
        throw FormatException('${entry.key} 取值无效');
    }
    for (final e in {
      'radius': [0, 28],
      'posterRadius': [0, 24],
      'blur': [0, 40],
      'opacity': [.65, .98],
    }.entries) {
      final v = d[e.key];
      if (v is! num || !v.isFinite || v < e.value[0] || v > e.value[1]) {
        throw FormatException('${e.key} 超出范围 ${e.value.join('–')}');
      }
    }
    final colors = d['colors'];
    if (colors is! Map ||
        roles.any((k) => colors[k] is! String) ||
        colors.keys.any((k) => !roles.contains(k))) {
      throw const FormatException('colors 必须包含完整的 11 个语义颜色');
    }
    for (final v in colors.values) {
      parseColor(v as String);
    }
    final spec = SkinSpec._(jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
    for (final surface in ['background', 'shell', 'panel']) {
      for (final foreground in ['text', 'muted']) {
        if (contrast(spec.color(foreground), spec.color(surface)) < 4.5) {
          throw FormatException('$foreground 与 $surface 的对比度不足 4.5:1，请调整颜色');
        }
      }
    }
    if (contrast(spec.color('accent'), spec.color('panel')) < 3) {
      throw const FormatException('强调色与面板的对比度不足 3:1');
    }
    return spec;
  }

  static SkinSpec decode(String text) {
    if (utf8.encode(text).length > 65536)
      throw const FormatException('皮肤文件不能超过 64 KB');
    final fence = RegExp(r'```(?:seewow-skin|json)\s*\n([\s\S]*?)```')
        .firstMatch(text);
    final decoded = jsonDecode((fence?[1] ?? text).trim());
    if (decoded is! Map<String, dynamic>)
      throw const FormatException('皮肤需要是 JSON 对象');
    return SkinSpec.fromJson(decoded);
  }

  /// Explicit token documents are deterministic and work without a model.
  static SkinSpec fromDesign(String markdown) {
    if (utf8.encode(markdown).length > 65536)
      throw const FormatException('design.md 不能超过 64 KB');
    if (markdown.trim().startsWith('{') ||
        markdown.contains('```seewow-skin') ||
        markdown.contains('```json')) {
      return decode(markdown);
    }
    final values = <String, String>{};
    for (final line in markdown.split('\n')) {
      final match = RegExp(r'^\s*\|?\s*([a-zA-Z]+)\s*(?::|\|)\s*`?([^|`\r\n]+)')
          .firstMatch(line);
      if (match != null) values[match[1]!] = match[2]!.trim();
    }
    if (!values.containsKey('mode')) {
      throw const FormatException(
        '本地生成需要 mode: dark / light 和语义颜色。可载入模板，或使用 AI 理解自由描述。',
      );
    }
    final base = (values['mode'] == 'light' ? builtInSkins[1] : builtInSkins[0])
        .toJson();
    final colors = Map<String, dynamic>.from(base['colors'] as Map);
    for (final k in roles) {
      if (values.containsKey(k)) colors[k] = values[k];
    }
    for (final k in [
      'name',
      'author',
      'description',
      'mode',
      'material',
      'font',
      'density',
    ]) {
      if (values.containsKey(k)) base[k] = values[k];
    }
    for (final k in ['radius', 'posterRadius', 'blur', 'opacity']) {
      if (values.containsKey(k))
        base[k] = double.tryParse(values[k]!) ?? values[k];
    }
    base['colors'] = colors;
    return SkinSpec.fromJson(base);
  }
}

SkinSpec _preset(
  String name,
  String description,
  String mode,
  List<String> colors, {
  String material = 'flat',
  String author = 'SeeWow',
}) => SkinSpec.fromJson({
  'schemaVersion': 1,
  'name': name,
  'author': author,
  'description': description,
  'mode': mode,
  'material': material,
  'colors': Map.fromIterables(SkinSpec.roles, colors),
});

final builtInSkins = <SkinSpec>[
  _preset('曜黑', '安静的中性黑，让影片成为主角。', 'dark', [
    '#090A0B',
    '#101113',
    '#18191C',
    '#F4F5F7',
    '#A6A9B0',
    '#858992',
    '#E5EAF2',
    '#303238',
    '#60738C',
    '#9AD4B5',
    '#FFB4AB',
  ]),
  _preset('素白', '干净的白与柔和灰，适合日间浏览。', 'light', [
    '#F4F5F7',
    '#EAECF0',
    '#FFFFFF',
    '#17191E',
    '#565D69',
    '#6D7480',
    '#243B59',
    '#D6DAE1',
    '#C7D7EA',
    '#256344',
    '#A63038',
  ]),
  _preset('流光玻璃', '低饱和流光、透光面板与局部磨砂。', 'dark', [
    '#0C111A',
    '#151E2C',
    '#1E293B',
    '#F1F5FC',
    '#BBC8DC',
    '#9BAFC8',
    '#B6D7FF',
    '#43536B',
    '#5578A6',
    '#A2DDC1',
    '#FFB4AB',
  ], material: 'glass'),
];

/// Local examples of the open format, not a remote community marketplace.
final communityExamples = <SkinSpec>[
  _preset('北境', '冷灰与冰蓝，紧凑的片库视图。', 'dark', [
    '#171D27',
    '#1D2531',
    '#263141',
    '#EDF2F8',
    '#B6C3D5',
    '#98A8BD',
    '#A3D6EE',
    '#445268',
    '#6B91AC',
    '#AFD4B2',
    '#FFB8BA',
  ], author: 'SeeWow · 开放格式示例').edit({'density': 'compact', 'radius': 12}),
  _preset('纸与墨', '暖白纸感，墨色文字与棕色强调。', 'light', [
    '#F4F0E8',
    '#EAE4D9',
    '#FFFCF6',
    '#28251F',
    '#665C50',
    '#7C7063',
    '#795331',
    '#D7CDBF',
    '#D0B58F',
    '#386343',
    '#A53636',
  ], author: 'SeeWow · 开放格式示例').edit({'font': 'editorial', 'radius': 8}),
];

String get skinDesignTemplate =>
    '''# 我的 SeeWow 皮肤

在这里补充视觉意图。下方参数可直接本地生成；自由描述也可交给已配置的 AI。

name: 我的曜黑
author: 我
mode: dark
material: flat
font: sans
density: comfortable
radius: 16
posterRadius: 10
blur: 24
opacity: 0.78

${SkinSpec.roles.map((k) => '$k: ${builtInSkins[0].data['colors'][k]}').join('\n')}
''';
