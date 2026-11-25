// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/liquid_nav.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/skin_spec.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/domain/media_item.dart';

/// Renders the real shell to PNG so the review has pictures instead of claims.
///
///   flutter test test/design_shots_test.dart
/// Output: /tmp/seewow-shots-new
Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(rootBundle.load(p));
  }
  await loader.load();
}

LibraryStore _demoStore() {
  final store = LibraryStore();
  store.items.addAll([
    MediaItem(
      id: 'dune2',
      sourceId: 'demo',
      kind: MediaKind.movie,
      title: 'Dune Part Two',
      locator: '/demo/Dune.Part.Two.2024.2160p.mkv',
      year: 2024,
      quality: '4K',
      rating: 8.5,
      genres: const ['科幻', '冒险'],
      overview: '保罗·厄崔迪与弗雷曼人并肩作战。',
      duration: 9960,
      position: 1793,
      addedAt: DateTime(2026, 10, 2),
    ),
    MediaItem(
      id: 'dark1',
      sourceId: 'demo',
      kind: MediaKind.episode,
      title: 'Dark S01E01',
      showTitle: 'Dark',
      season: 1,
      episode: 1,
      locator: '/demo/Dark.S01E01.mkv',
      year: 2017,
      quality: '1080P',
      rating: 8.7,
      genres: const ['悬疑'],
      overview: '一个孩子的失踪。',
      duration: 3120,
      position: 1380,
      addedAt: DateTime(2026, 9, 20),
    ),
  ]);
  return store;
}

void main() {
  setUpAll(() async {
    await _loadFont('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
    final cjk = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (cjk.existsSync()) {
      final data = await cjk.readAsBytes();
      // Register the same face under every family the skin's fallback chain
      // names, so a screenshot is not a picture of Ahem boxes.
      for (final family in [
        'PingFang SC',
        'Songti SC',
        'STSong',
        'Noto Serif CJK SC',
        'Source Han Serif SC',
        'Noto Serif SC',
        'Noto Sans CJK SC',
        'Microsoft YaHei',
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(data)));
        await loader.load();
      }
    }
    await _loadFont('SourceSerif4', [
      'assets/fonts/SourceSerif4-Regular.otf',
      'assets/fonts/SourceSerif4-Semibold.otf',
      'assets/fonts/SourceSerif4-Bold.otf',
    ]);
    await _loadFont('JetBrainsMono', [
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/JetBrainsMono-Medium.ttf',
      'assets/fonts/JetBrainsMono-SemiBold.ttf',
    ]);
  });

  testWidgets('shell shots', (tester) async {
    final dir = Directory('/tmp/seewow-shots-new')..createSync(recursive: true);
    final key = GlobalKey();
    final store = _demoStore();
    final iptv = IPTVStore();
    WowSkin.I.use(builtInSkins[2]); // 流光玻璃：这一轮改的就是玻璃材质

    // Test-only cosmetics: flutter_test has no system font fallback, so any
    // style without a registered family draws Ahem's boxes. Point every text
    // style at the loaded CJK face so the screenshot shows the app, not the
    // harness.
    final base = buildWowTheme();
    const cjk = TextStyle(fontFamily: 'PingFang SC');
    final theme = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'PingFang SC'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'PingFang SC'),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: const WidgetStatePropertyAll(cjk),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(textStyle: const WidgetStatePropertyAll(cjk)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: const WidgetStatePropertyAll(cjk),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(labelStyle: cjk),
      dropdownMenuTheme: base.dropdownMenuTheme.copyWith(textStyle: cjk),
      listTileTheme: base.listTileTheme.copyWith(
        titleTextStyle: cjk,
        subtitleTextStyle: cjk,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: cjk.copyWith(color: const Color(0xFF8A8F99)),
      ),
      dialogTheme: base.dialogTheme.copyWith(titleTextStyle: cjk),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: cjk,
      ),
    );

    Future<void> pumpShell() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: AppShell(key: UniqueKey(), store: store, iptv: iptv, online: OnlineSourceStore.empty()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File(dir.path + '/' + name + '.png').writeAsBytesSync(bytes!);
      print('shot ' + name + ' (' + bytes.length.toString() + ' bytes)');
    }

    // Desktop first: a fresh shell, so the picture is the home feed and not
    // whatever the phone run navigated to last.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpShell();
    await shoot('desktop-home');

    // Phone.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpShell();
    await shoot('phone-home');
    if (find.text('片库').evaluate().isNotEmpty) {
      await tester.tap(find.text('片库').last);
      await tester.pumpAndSettle();
      await shoot('phone-library');
    }
    if (find.text('Agent').evaluate().isNotEmpty) {
      await tester.tap(find.text('Agent').last);
      await tester.pumpAndSettle();
      await shoot('phone-agent');
    }
    // 片源与订阅不再占导航席：手机顶栏的图标就是入口。
    final sourcesEntry = find.byTooltip('片源与订阅');
    if (sourcesEntry.evaluate().isNotEmpty) {
      await tester.tap(sourcesEntry.first);
      await tester.pumpAndSettle();
      await shoot('phone-sources');
    }
    // The fifth seat: back to home first (it names the page you stand on),
    // then tap twice — once to stand on it, once to open the shelf.
    if (find.text('放映').evaluate().isNotEmpty) {
      await tester.tap(find.text('放映').last);
      await tester.pumpAndSettle();
    }
    Finder seat() => find.descendant(
      of: find.byType(LiquidTabBar),
      matching: find.text('短剧'),
    );
    if (seat().evaluate().isNotEmpty) {
      await tester.tap(seat().first);
      await tester.pumpAndSettle();
      await tester.tap(seat().first);
      await tester.pumpAndSettle();
      await shoot('phone-more-sheet');
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
    }

    // 暗房皮肤（本轮新默认）：同一个壳、同一个片库，只换皮肤，用来对比。
    WowSkin.I.use(builtInSkins[0]);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    await pumpShell();
    await shoot('desktop-home-darkroom');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await pumpShell();
    await shoot('phone-home-darkroom');
    if (find.text('片库').evaluate().isNotEmpty) {
      await tester.tap(find.text('片库').last);
      await tester.pumpAndSettle();
      await shoot('phone-library-darkroom');
    }

    expect(tester.takeException(), isNull);
  });
}
