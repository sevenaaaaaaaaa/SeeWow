import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/film_rail.dart';

/// 轨上的预览位：有图才浮，没图就是 null——绝不出现"假装有一帧"的空白卡片。

void main() {
  Future<void> pump(WidgetTester tester, {Widget? preview}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 32,
              child: FilmRail(
                duration: 7200,
                position: 3600,
                preview: preview,
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('没有预览时不布置任何多余的东西', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('rail-preview')), findsNothing);
  });

  testWidgets('给了预览就贴着游标浮在轨上方', (tester) async {
    await pump(
      tester,
      preview: const SizedBox(
        key: ValueKey('rail-preview'),
        width: 168,
        height: 94,
      ),
    );
    final railRect = tester.getRect(find.byType(FilmRail));
    final previewRect = tester.getRect(find.byKey(const ValueKey('rail-preview')));
    expect(previewRect.width, 168);
    // 游标在中间：预览中心应落在轨的中点附近
    expect(previewRect.center.dx, closeTo(railRect.center.dx, 6));
    // 在轨的上方，而不是压在轨上
    expect(previewRect.bottom, lessThanOrEqualTo(railRect.top));
  });
}
