import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/design/liquid_nav.dart';
import 'package:seewow/domain/online_source.dart';

/// 1.21.2 把源包塞进了包里，入口却留在「更多」弹层：底部第 5 席写着「短剧」，
/// 要点两次才到「在线源」，首页一个字没提。这条测试钉住入口本身——源包再好，
/// 找不到就等于没有。
void main() {
  testWidgets('手机宽度下，底部第五席默认就是「在线源」，一点直达', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final online = OnlineSourceStore.empty();
    await online.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
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
    await tester.pumpAndSettle();

    // 第五席的标签就是入口：里面写的是「在线源」，不是「短剧」也不是「更多」。
    final seat = find.descendant(
      of: find.byType(LiquidTabBar),
      matching: find.text('在线源'),
    );
    expect(seat, findsOneWidget, reason: '第五席要直接写「在线源」');
    expect(
      find.descendant(of: find.byType(LiquidTabBar), matching: find.text('短剧')),
      findsNothing,
      reason: '第五席不该再默认顶着「短剧」',
    );

    await tester.tap(seat);
    await tester.pumpAndSettle();

    // 进来就是可搜的页面：站点数、搜索模式、空态说明。
    expect(
      find.textContaining('${seedOnlineSites.length}  SITES'),
      findsOneWidget,
      reason: '标题下要写清楚内置了几个站',
    );
    expect(find.text('片名搜索'), findsOneWidget);
    expect(find.textContaining('问一遍已启用的'), findsOneWidget);
  });
}
