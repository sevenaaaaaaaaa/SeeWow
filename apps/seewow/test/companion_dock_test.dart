import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/features/watch_ai_view.dart';
import 'package:seewow/playback/companion_dock.dart';
import 'package:seewow/watch_ai/watch_ai_client.dart';
import 'package:seewow/watch_ai/watch_ai_controller.dart';
import 'package:seewow/watch_ai/watch_ai_settings.dart';

class _Client extends WatchAiClient {
  _Client(super.settings);
  @override
  Future<String> complete({
    required WatchAiConfig config,
    required String system,
    required String prompt,
    Uint8List? frame,
  }) async => '好';
}

void main() {
  testWidgets('浮窗：展开是卡、抓手能拖、越界会夹住、收起是球', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var collapsed = false, expands = 0;
    late StateSetter flip;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              flip = setState;
              return Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.black)),
                  CompanionDock(
                    collapsed: collapsed,
                    onCollapse: () => flip(() => collapsed = true),
                    onExpand: () => expands++,
                    panel: const Center(child: Text('面板')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('companionCard')), findsOneWidget);
    expect(find.text('面板'), findsOneWidget, reason: '展开时面板要真的在');

    final before = tester.getTopLeft(
      find.byKey(const ValueKey('companionCard')),
    );
    await tester.drag(
      find.byKey(const ValueKey('companionGrip')),
      // 默认贴右下角，往左下太多会先撞到边，所以这里只挪一小步。
      const Offset(-20, -12),
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pump();
    final after = tester.getTopLeft(
      find.byKey(const ValueKey('companionCard')),
    );
    expect(after.dx, closeTo(before.dx - 20, 1), reason: '抓手就是拖动区');
    expect(after.dy, closeTo(before.dy - 12, 1));

    await tester.drag(
      find.byKey(const ValueKey('companionGrip')),
      const Offset(-4000, -4000),
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pump();
    final clamped = tester.getTopLeft(
      find.byKey(const ValueKey('companionCard')),
    );
    expect(clamped.dx, closeTo(8, .5), reason: '不许拖出左边界');
    expect(clamped.dy, closeTo(8, .5), reason: '不许拖出上边界');

    flip(() => collapsed = true);
    await tester.pump();
    expect(find.byKey(const ValueKey('companionCard')), findsNothing);
    expect(find.byKey(const ValueKey('companionBubble')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('companionBubble')));
    expect(expands, 1, reason: '点球要展开');
  });

  testWidgets('面板在浮窗里给出「收起」与「关闭」，且都不再走 pop', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = WatchAiSettings();
    final ai = WatchAiController(
      title: 'Film',
      settings: settings,
      client: _Client(settings),
    );
    addTearDown(() {
      ai.dispose();
      settings.dispose();
    });

    var collapses = 0, closes = 0;
    Future<void> mount({VoidCallback? onClose}) => tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: Scaffold(
          body: WatchCompanionPanel(
            controller: ai,
            capture: () async => Uint8List(0),
            onImportSubtitle: () async {},
            onSelectSubtitle: () async {},
            onCollapse: () => collapses++,
            onClose: onClose,
          ),
        ),
      ),
    );

    await mount(onClose: () => closes++);
    await tester.pump();
    expect(find.byTooltip('关闭陪看'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭陪看'));
    expect(closes, 1, reason: '关闭要回给浮窗，而不是退掉播放器路由');
    await tester.tap(find.byTooltip('收起（Esc）'));
    expect(collapses, 1);

    await mount();
    await tester.pump();
    expect(find.byTooltip('关闭陪看'), findsNothing, reason: '没有关闭回调时不摆这个按钮');
  });
}
