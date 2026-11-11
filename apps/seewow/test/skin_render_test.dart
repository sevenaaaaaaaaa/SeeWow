import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/tokens.dart';
import 'package:seewow/design/skin_spec.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/features/skin_studio.dart';
import 'package:seewow/features/settings_view.dart';
import 'package:seewow/domain/media_item.dart';

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
      overview: '保罗·厄崔迪与弗雷曼人并肩作战，在沙丘星球上向摧毁他家族的阴谋者展开复仇。权力、预言与牺牲在无尽的黄沙中交织。',
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
      overview: '一个孩子的失踪，撕开四个家庭与一座小镇的秘密。',
      duration: 3120,
      position: 1380,
      addedAt: DateTime(2026, 9, 20),
    ),
    MediaItem(
      id: 'dark2',
      sourceId: 'demo',
      kind: MediaKind.episode,
      title: 'Dark S01E02',
      showTitle: 'Dark',
      season: 1,
      episode: 2,
      locator: '/demo/Dark.S01E02.mkv',
      year: 2017,
      quality: '1080P',
      rating: 8.6,
      genres: const ['悬疑'],
      overview: '时间开始折叠，过去与现在互相注视。',
      duration: 3180,
      position: 1440,
      addedAt: DateTime(2026, 9, 21),
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
      final loader = FontLoader('PingFang SC')
        ..addFont(Future.value(ByteData.sublistView(data)));
      await loader.load();
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

  testWidgets('skin presets repaint the shell', (tester) async {
    tester.view.physicalSize = const Size(1486, 1046);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final store = _demoStore();
    final iptv = IPTVStore();

    Future<void> shoot(String name) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildWowTheme().copyWith(
            textTheme: buildWowTheme().textTheme.apply(
              fontFamily: 'PingFang SC',
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: WowColors.ink,
              body: AppShell(store: store, iptv: iptv),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('SeeWow').first)).brightness,
        WowSkin.I.isLight ? Brightness.light : Brightness.dark,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('SeeWow').first))
            .style
            .color,
        WowColors.text,
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      expect(bytes!.length, greaterThan(20000));
      if (Platform.environment['SEEWOW_SHOTS'] == '1') {
        final dir = Directory('/tmp/seewow-shots')..createSync(recursive: true);
        File('${dir.path}/skin-$name.png').writeAsBytesSync(bytes);
      }
    }

    for (var i = 0; i < builtInSkins.length; i++) {
      WowSkin.I.use(builtInSkins[i]);
      await shoot(['black', 'white', 'glass'][i]);
      expect(tester.takeException(), isNull);
    }

    // The switcher itself has to render, not only the palettes behind it.
    WowSkin.I.use(builtInSkins.first);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildWowTheme(),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: WowColors.ink,
            body: SettingsView(store: store),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final settingsBytes = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(settingsBytes!.length, greaterThan(20000));
    if (Platform.environment['SEEWOW_SHOTS'] == '1') {
      File('/tmp/seewow-shots/skin-e-settings.png')
          .writeAsBytesSync(settingsBytes);
    }
  });
  testWidgets(
    'design generation previews and cancel preserves current skin at 375px',
    (tester) async {
      tester.view.physicalSize = const Size(375, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      WowSkin.I.reset();
      final initial = WowSkin.I.spec.encode();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWowTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const SkinStudioDialog(initialTab: 2),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'mode: light\nname: 生成的白色',
      );
      await tester.ensureVisible(find.text('本地生成预览'));
      await tester.tap(find.text('本地生成预览'));
      await tester.pumpAndSettle();
      expect(find.text('生成的白色'), findsOneWidget);
      expect(WowSkin.I.spec.encode(), initial);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(WowSkin.I.spec.encode(), initial);
    },
  );

  testWidgets('community import applies only a validated preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    WowSkin.I.reset();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const SkinStudioDialog(initialTab: 1),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{"schemaVersion": 99}');
    await tester.tap(find.text('校验并预览'));
    await tester.pumpAndSettle();
    expect(find.text('仅支持 schemaVersion: 1'), findsOneWidget);
    expect(WowSkin.I.spec.name, builtInSkins.first.name);
    await tester.enterText(
      find.byType(TextField),
      communityExamples.first.encode(),
    );
    await tester.tap(find.text('校验并预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用并保存'));
    await tester.pumpAndSettle();
    expect(WowSkin.I.spec.name, communityExamples.first.name);
    expect(tester.takeException(), isNull);
    WowSkin.I.reset();
  });
}
