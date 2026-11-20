import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/library_view.dart';

MediaItem _item(String id, String title) => MediaItem(
  id: id,
  sourceId: 's1',
  kind: MediaKind.movie,
  title: title,
  locator: '/tmp/$id.mp4',
);

Future<void> _pump(WidgetTester tester, LibraryStore store) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LibraryView(store: store, onOpen: (_) {}, onPlay: (_) {}),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late LibraryStore store;

  setUp(() {
    store = LibraryStore();
    store.items.addAll([
      _item('a', '第一部'),
      _item('b', '第二部'),
    ]);
  });

  testWidgets('筛选区在手机上只占两行，不再把结果压到半屏以下', (tester) async {
    await _pump(tester, store);
    final chipRow = tester.getRect(find.text('筛选'));
    final countRow = tester.getRect(find.textContaining('个条目'));
    final blockHeight = countRow.bottom - chipRow.top;
    // 旧布局：分类一行 + 五个下拉三行 + 状态一行 ≈ 300pt 以上。
    // 改版后实测 49pt（旧布局 ≈ 278pt）；给到 70pt 留一点字体缩放余量。
    expect(blockHeight, lessThan(70));
    expect(chipRow.top, lessThan(340));
  });

  testWidgets('五个下拉都在「筛选」面板里，不再平铺在页面上', (tester) async {
    await _pump(tester, store);
    expect(find.text('全部来源'), findsNothing);
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    expect(find.text('全部来源'), findsOneWidget);
    expect(find.text('全部类型'), findsOneWidget);
    expect(find.text('全部媒体'), findsOneWidget);
    expect(find.text('最近添加'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('待整理与已缓存仍在第一行，点一下能开', (tester) async {
    await _pump(tester, store);
    final chip = find.textContaining('待整理 ·');
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();
    expect(find.textContaining('缺信息'), findsWidgets);
  });
}
