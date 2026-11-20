import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/features/settings_view.dart';

void main() {
  test('设置里的「对话框型」设置都能从调色板直达', () {
    final commands = wowSettingsCommands();
    expect(commands.length, greaterThanOrEqualTo(7));
    final labels = commands.map((c) => c.label).toList();
    expect(labels.toSet().length, labels.length, reason: '标签不应重复');
    expect(labels, contains('放映与播放'));
    expect(labels, contains('在线字幕服务'));
  });

  testWidgets('顶栏搜索打开调色板，并列出设置入口', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = LibraryStore();
    final iptv = IPTVStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: AppShell(store: store, iptv: iptv, online: OnlineSourceStore.empty()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索你的影院').first);
    await tester.pumpAndSettle();

    // 目的地照旧，设置现在也在同一个词下面（要往下滚才看得到，所以滚动到它）。
    expect(find.text('为你放映'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('放映与播放'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('放映与播放'), findsOneWidget);
    expect(find.text('在线字幕服务'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
