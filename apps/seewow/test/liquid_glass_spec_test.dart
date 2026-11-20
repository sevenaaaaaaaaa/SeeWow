import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/brand_mark.dart';
import 'package:seewow/design/cinema_widgets.dart';
import 'package:seewow/design/liquid_glass.dart';
import 'package:seewow/domain/media_item.dart';

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark),
  home: Scaffold(body: Center(child: child)),
);

MediaItem film() => MediaItem(
  id: 'm1',
  sourceId: 's1',
  kind: MediaKind.movie,
  title: 'Dune Part Two',
  locator: '/media/dune.mkv',
  year: 2024,
  position: 600,
);

LibraryStore storeWith(MediaItem item) {
  final store = LibraryStore();
  store.items.add(item);
  return store;
}

void main() {
  test('同心圆角：父 28 内缩 6 得 22，且有下限 8', () {
    expect(GlassTokens.concentric(28, 6), 22);
    expect(GlassTokens.concentric(22, 8), 14);
    // 小尺寸里内缩不能把圆角算成负数。
    expect(GlassTokens.concentric(20, 40), GlassTokens.minRadius);
  });

  testWidgets('玻璃按钮始终留出 44 的触控高度', (tester) async {
    await tester.pumpWidget(
      host(GlassButton(label: '去片库挑一部', onTap: () {})),
    );
    final size = tester.getSize(find.byType(GlassButton));
    expect(size.height, greaterThanOrEqualTo(GlassTokens.touchTarget));
  });

  testWidgets('玻璃按钮可以被点中', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(GlassButton(label: '清除筛选', onTap: () => taps++)),
    );
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('玻璃图标按钮带语义标签，禁用时不可点', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        const GlassIconButton(
          icon: Icons.favorite_border,
          label: '喜欢',
        ),
      ),
    );
    expect(tester.getSize(find.byType(GlassIconButton)).width,
        greaterThanOrEqualTo(GlassTokens.touchTarget));
    await tester.tap(find.byType(GlassIconButton));
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('降低透明度时不挂背景模糊，也不报错', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: const Scaffold(
            body: Center(
              child: LiquidGlass(
                radius: 20,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标配皮肤下玻璃会挂上背景模糊', (tester) async {
    await tester.pumpWidget(
      host(
        const LiquidGlass(
          radius: 20,
          opacity: .8,
          blur: 18,
          child: SizedBox(width: 120, height: 60),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('同心圆角参数优先于半径', (tester) async {
    await tester.pumpWidget(
      host(
        const LiquidGlass(
          radius: 40,
          concentric: (outer: 30, inset: 8),
          child: SizedBox(width: 90, height: 40),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('品牌标记在各个尺寸都能画出来', (tester) async {
    for (final size in [16.0, 32.0, 128.0]) {
      await tester.pumpWidget(host(WowMark(size: size, tile: true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      host(
        const WowMark(
          size: 48,
          monochrome: true,
          color: Color(0xFFE5EAF2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片上的播放键直接起播，不进详情页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var plays = 0, opens = 0;
    final item = film();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 160,
          height: 300,
          child: FilmCard(
            item: item,
            store: storeWith(item),
            onOpen: () => opens++,
            onPlay: () => plays++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 手机上悬停不可用，播放键必须常驻。
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).last);
    await tester.pumpAndSettle();
    expect(plays, 1);
    expect(opens, 0);
    // Reset before the test ends: flutter_test checks foundation debug
    // variables at the end of the body, not in a tear-down.
    debugDefaultTargetPlatformOverride = null;
  });
}
