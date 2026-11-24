import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/data/online_source_store.dart';

/// 手机顶栏曾经只留标题、搜索和两个图标，「设置」退到「更多」弹层里，
/// 而且要先站在某个溢出分区、再点一次同一个座位才打得开。用户的原话是
/// 「设置入口没有」——要两次点、还得先猜到，就是没有。
void main() {
  for (final size in const [Size(390, 844), Size(744, 1000)]) {
    testWidgets('${size.width.toInt()}px 下顶栏有常驻「设置」，一点就到设置页', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final online = OnlineSourceStore.empty();
      await online.load();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppShell(
              store: LibraryStore(),
              iptv: IPTVStore(),
              online: online,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(
        tester.takeException(),
        isNull,
        reason: '加了设置图标之后顶栏不能挤出屏幕',
      );

      final gear = find.byTooltip('设置');
      expect(gear, findsOneWidget, reason: '窄屏顶栏要有一个常驻的设置入口');

      await tester.tap(gear);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('外观与氛围'), findsOneWidget, reason: '点设置要直接落到设置页');
    });
  }
}
