import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/escape.dart';
import 'package:seewow/features/settings_status.dart';
import 'package:seewow/features/settings_view.dart';

void main() {
  test('配置状态在没有插件、没有配置文件时也给出结论', () async {
    final snapshot = await AiStatusSnapshot.load();
    // 测试环境没有 path_provider，读不到就按「未配置」算，不能抛。
    expect(snapshot.voice.configured, isFalse);
    expect(snapshot.cover.configured, isFalse);
    expect(snapshot.scrapers.configured, isFalse);
    expect(snapshot.metadata.configured, isFalse);
    expect(snapshot.configuredCount, inInclusiveRange(0, 5));
  });

  testWidgets('设置页 AI 分组每一行都有状态胶囊', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsView(store: LibraryStore()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // 四行曾经只有说明文字，没有状态；现在都有胶囊。
    expect(find.text('未配置'), findsWidgets);
    expect(find.text('AI 模型'), findsOneWidget);
    expect(find.text('AI 封面服务'), findsOneWidget);
    expect(find.text('自定义刮削 API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc 按最内层界面处理：详情这样的页面会被关掉', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EscapeToPop(
                      child: Scaffold(
                        body: Center(
                          // 页面里得有一个可聚焦的东西，焦点落在这一层
                          // 快捷键才会命中。
                          child: Focus(
                            autofocus: true,
                            child: Text('里面的页面'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('里面的页面'), findsOneWidget);

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('里面的页面'), findsNothing);
  });
}
