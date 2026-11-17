import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/poster_tile.dart';
import 'package:seewow/design/pressable.dart';
import 'package:seewow/domain/media_item.dart';

MediaItem film({String? poster}) => MediaItem(
  id: 'm1',
  sourceId: 's1',
  kind: MediaKind.movie,
  title: 'Dune Part Two',
  locator: '/media/dune.mkv',
  year: 2024,
  posterUrl: poster,
);

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('Pressable 可以用 Enter 激活', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Pressable(
          onTap: () => taps++,
          child: const SizedBox(width: 60, height: 60),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Pressable 没有 onTap 时键盘不会触发任何动作', (tester) async {
    await tester.pumpWidget(
      host(const Pressable(child: SizedBox(width: 60, height: 60))),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('占位海报不再把标题重复写在下面', (tester) async {
    await tester.pumpWidget(host(PosterTile(item: film(), width: 160)));
    await tester.pumpAndSettle();
    // 画面上只有占位海报里的那一份标题（大写），下面不再重复。
    expect(find.text('DUNE PART TWO'), findsOneWidget);
    expect(find.text('Dune Part Two'), findsNothing);
  });

  testWidgets('有真海报时保留标题行，方便扫读', (tester) async {
    await tester.pumpWidget(
      host(PosterTile(item: film(poster: 'https://example.invalid/p.jpg'), width: 160)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dune Part Two'), findsOneWidget);
  });

  testWidgets('减弱动态效果时不报错也不留未完成动画', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(Pressable(onTap: () {}, child: PosterTile(item: film(), width: 120))),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}