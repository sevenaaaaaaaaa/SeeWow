import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/liquid_glass.dart';
import 'package:seewow/design/liquid_nav.dart';

const _tabs = [
  LiquidTab(label: '放映', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
  LiquidTab(
    label: '片库',
    icon: Icons.video_library_outlined,
    activeIcon: Icons.video_library_rounded,
  ),
  LiquidTab(
    label: 'Agent',
    icon: Icons.auto_awesome_outlined,
    activeIcon: Icons.auto_awesome,
  ),
  LiquidTab(label: '片源', icon: Icons.hub_outlined, activeIcon: Icons.hub_rounded),
  LiquidTab(
    label: '短剧',
    icon: Icons.movie_filter_outlined,
    activeIcon: Icons.movie_filter,
  ),
];

Future<void> _pump(WidgetTester tester, {int index = 0}) async {
  tester.view.physicalSize = const Size(1290, 2796); // iPhone 15 Pro Max
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: LiquidTabBar(
            tabs: _tabs,
            index: index,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('每个 tab 的图标与文字都落在自己那一格里，不向左偏', (tester) async {
    await _pump(tester);
    for (var i = 0; i < _tabs.length; i++) {
      final seat = tester.getRect(find.byType(PressableLens).at(i));
      final label = tester.getRect(find.text(_tabs[i].label));
      expect(
        (label.center.dx - seat.center.dx).abs(),
        lessThan(0.6),
        reason: '座位 $i 的文字中心应贴在座位中线上',
      );
      expect(label.left, greaterThanOrEqualTo(seat.left - 0.5));
      expect(label.right, lessThanOrEqualTo(seat.right + 0.5));
    }
  });

  testWidgets('图标同样居中，且整排竖着留在 bar 里', (tester) async {
    await _pump(tester);
    final bar = tester.getRect(find.byType(LiquidTabBar));
    for (var i = 0; i < _tabs.length; i++) {
      final seat = tester.getRect(find.byType(PressableLens).at(i));
      final icon = tester.getRect(
        find.byIcon(i == 0 ? (_tabs[i].activeIcon ?? _tabs[i].icon) : _tabs[i].icon),
      );
      expect((icon.center.dx - seat.center.dx).abs(), lessThan(1.5));
      expect(icon.top, greaterThanOrEqualTo(bar.top - 1));
      final label = tester.getRect(find.text(_tabs[i].label));
      expect(label.bottom, lessThanOrEqualTo(bar.bottom + 1));
    }
  });

  testWidgets('换到第 3 个座位时，选中态不影响其它格的对齐', (tester) async {
    await _pump(tester, index: 2);
    for (var i = 0; i < _tabs.length; i++) {
      final seat = tester.getRect(find.byType(PressableLens).at(i));
      final label = tester.getRect(find.text(_tabs[i].label));
      expect((label.center.dx - seat.center.dx).abs(), lessThan(0.6));
    }
  });
}
