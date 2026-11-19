import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/liquid_nav.dart';

const _tabs = [
  LiquidTab(label: '放映', icon: Icons.home_outlined),
  LiquidTab(label: '片库', icon: Icons.video_library_outlined),
  LiquidTab(label: 'Agent', icon: Icons.auto_awesome_outlined),
  LiquidTab(
    label: '片源',
    icon: Icons.hub_outlined,
    activeIcon: Icons.hub_rounded,
  ),
  LiquidTab(label: '更多', icon: Icons.more_horiz),
];

void main() {
  testWidgets('the bar shows five seats and reports the one that was tapped', (
    tester,
  ) async {
    var index = 0;
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) => LiquidTabBar(
              tabs: _tabs,
              index: index,
              onSelect: (i) {
                picked.add(i);
                setState(() => index = i);
              },
            ),
          ),
        ),
      ),
    );

    for (final tab in _tabs) {
      expect(find.text(tab.label), findsOneWidget);
    }

    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    await tester.tap(find.text('片源'));
    await tester.pump(const Duration(milliseconds: 1000));

    expect(picked, [3]);
    expect(find.byIcon(Icons.hub_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('tapping the seat already selected does nothing', (tester) async {
    var index = 0;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) => LiquidTabBar(
              tabs: _tabs,
              index: index,
              onSelect: (i) {
                calls++;
                setState(() => index = i);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('放映'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 0);
  });

  testWidgets('the bar keeps its shape when the system asks for less motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LiquidTabBar(tabs: _tabs, index: 2, onSelect: _noop),
          ),
        ),
      ),
    );
    expect(find.text('Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop(int _) {}
