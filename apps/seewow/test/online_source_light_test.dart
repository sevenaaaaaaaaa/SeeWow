import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/skin_spec.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/design/tokens.dart';
import 'package:seewow/features/online_source_view.dart';

/// 素白皮肤上线时，「在线源」整屏是按深色皮肤写死的白色半透明——白底上的
/// 0.30 白只有 1.1:1，等于把标题、站点数、空态说明全擦掉。这条测试把
/// 「看得见」变成可判定的数字：屏幕上每一行字与它所在背景的对比度必须
/// 过 WCAG AA（正文 4.5:1，大字 3:1）。
double _contrast(Color fg, Color bg) {
  final front = Color.alphaBlend(fg, bg).computeLuminance();
  final back = bg.computeLuminance();
  final hi = math.max(front, back);
  final lo = math.min(front, back);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets('素白皮肤下，「在线源」每一行字都读得出来', (tester) async {
    // 不调 WowSkin.I.load()：它要等 path_provider 的平台通道，而 testWidgets
    // 的假时钟不会推进平台消息，await 会一直挂着。直接切皮肤就够了。
    WowSkin.I.use(builtInSkins[1]); // 素白
    expect(WowSkin.I.isLight, isTrue);

    // 内存清单：测试里不碰磁盘，也不碰 path_provider 的平台通道。
    final store = OnlineSourceStore.empty();
    await store.load();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildWowTheme(),
        home: Scaffold(
          backgroundColor: WowColors.ink,
          body: OnlineSourceView(
            store: store,
            iptv: IPTVStore(),
            onPlay: (_, {live = false}) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final background = WowColors.ink;
    final failures = <String>[];
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final style = text.style;
      final color = style?.color;
      if (color == null) continue;
      final size = style?.fontSize ?? 12;
      final need = size >= 18.66 ? 3.0 : 4.5;
      final ratio = _contrast(color, background);
      if (ratio + 0.005 < need) {
        failures.add(
          '「${text.data ?? text.textSpan?.toPlainText() ?? '(富文本)'}」'
          '${ratio.toStringAsFixed(2)}:1 < ${need.toStringAsFixed(1)}:1',
        );
      }
    }

    // 提示语由 InputDecorator 直接绘制，不在 Text 列表里，单独量一次。
    final field = tester.widget<TextField>(find.byType(TextField).first);
    final decoration = field.decoration!;
    final fill = Color.alphaBlend(
      decoration.fillColor ?? Colors.transparent,
      background,
    );
    final hint = decoration.hintStyle?.color;
    if (hint != null) {
      final ratio = _contrast(hint, fill);
      if (ratio + 0.005 < 4.5) {
        failures.add(
          '搜索提示「${decoration.hintText}」${ratio.toStringAsFixed(2)}:1 < 4.5:1',
        );
      }
    }

    expect(failures, isEmpty, reason: '素白皮肤下这些文字看不见：\n${failures.join('\n')}');
  });

  test('深色皮肤的叠白行为保持不变', () {
    WowSkin.I.use(builtInSkins[0]); // 曜黑
    expect(WowSkin.I.isLight, isFalse);
    final color = WowColors.fade(0.34);
    expect((color.a * 1000).round(), 340);
    expect((color.r * 255).round(), 255);
  });

  test('「在线源」与「作品详情」不再硬编码白色', () {
    for (final path in [
      'lib/features/online_source_view.dart',
      'lib/features/work_detail_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('Colors.white'),
        isFalse,
        reason:
            '$path 里还有 Colors.white：浅色皮肤上它就是隐形的，'
            '请改用 WowColors.fade() / WowColors.wash()',
      );
    }
  });
}
