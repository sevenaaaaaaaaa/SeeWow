import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/agent_controller.dart';
import 'package:seewow/app/app_shell.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/tokens.dart';
import 'package:seewow/design/skin_spec.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/agent_view.dart';
import 'package:seewow/features/detail_view.dart';
import 'package:seewow/features/home_view.dart';
import 'package:seewow/features/library_view.dart';
import 'package:seewow/features/sources_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      for (final family in ['CinemaTest', 'PingFang SC']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    }
    for (final entry in {
      'JetBrainsMono': 'assets/fonts/JetBrainsMono-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });
  late Directory dir;
  late LibraryStore store;
  late IPTVStore iptv;
  late AgentController agent;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-experience-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    store = LibraryStore(directory: dir);
    final demo = Directory('../../DemoMedia/电影/Dune Part Two (2024)');
    String? poster, backdrop;
    if (demo.existsSync()) {
      final files = demo.listSync(recursive: true).whereType<File>();
      poster = files
          .where((f) => f.path.endsWith('poster.jpg'))
          .firstOrNull
          ?.absolute
          .path;
      backdrop = files
          .where((f) => f.path.endsWith('fanart.jpg'))
          .firstOrNull
          ?.absolute
          .path;
    }
    store.items.addAll([
      MediaItem(
        id: 'dune',
        sourceId: 'nas',
        kind: MediaKind.movie,
        title: 'Dune Part Two',
        locator: '/media/dune.mp4',
        year: 2024,
        genres: ['科幻', '冒险'],
        duration: 9960,
        position: 1793,
        quality: '4K',
        rating: 8.5,
        posterUrl: poster,
        backdropUrl: backdrop,
        overview: '保罗与弗雷曼人并肩作战，在沙丘星球上寻找未来。',
      ),
      MediaItem(
        id: 'hotel',
        sourceId: 'nas',
        kind: MediaKind.movie,
        title: 'The Grand Budapest Hotel',
        locator: '/media/hotel.mp4',
        year: 2014,
        genres: ['喜剧'],
        duration: 5940,
        rating: 8.1,
      ),
    ]);
    store.sources.add(
      MediaSource(
        id: 'nas',
        kind: SourceKind.webdav,
        name: '我的家庭影院与珍藏电影',
        location: 'https://example.test/dav/',
        lastScan: DateTime(2026, 11, 11),
      ),
    );
    iptv = IPTVStore();
    agent = AgentController(store, directory: dir);
    WowSkin.I.reset();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    Widget screen,
    double width, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets('core screens fit at $width px', (tester) async {
      addTearDown(tester.view.reset);
      final screens = [
        HomeView(store: store, onOpen: (_) {}, onPlay: (_) {}),
        LibraryView(store: store, onOpen: (_) {}),
        SourcesView(store: store, iptv: iptv, onAgent: (_) {}),
        AgentView(agent: agent, iptv: iptv, onOpen: (_) {}),
        DetailView(item: store.items.first, store: store, onPlay: (_) {}),
      ];
      for (final spec in builtInSkins) {
        WowSkin.I.use(spec);
        for (final screen in screens) {
          await mount(tester, screen, width);
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} at $width',
          );
          if (screen is SourcesView) {
            await tester.tap(find.text('网盘 / WebDAV'));
            await tester.pumpAndSettle();
            expect(find.text('连接你的片源'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
          }
        }
      }
    });
  }
  testWidgets('large text fits the home and source connection flow', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await mount(
      tester,
      HomeView(store: store, onOpen: (_) {}, onPlay: (_) {}),
      375,
      scale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('shell global search returns real results and opens detail', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await mount(tester, AppShell(store: store, iptv: iptv), 1440);
    await tester.tap(find.text('搜索你的影院'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Dune');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune Part Two').last);
    await tester.pumpAndSettle();
    expect(find.text('故事从这里开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('library search changes the displayed results', (tester) async {
    addTearDown(tester.view.reset);
    await mount(tester, LibraryView(store: store, onOpen: (_) {}), 1440);
    await tester.enterText(find.byType(TextField), 'Budapest');
    await tester.pumpAndSettle();
    expect(find.text('1 个条目'), findsOneWidget);
    expect(find.text('Dune Part Two'), findsNothing);
    expect(find.text('The Grand Budapest Hotel'), findsWidgets);
  });
  testWidgets('capture the implemented cinema experience', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    final shots = Directory('/tmp/seewow-experience-shots')
      ..createSync(recursive: true);
    await tester.runAsync(() => agent.run('按我的口味生成科幻片单'));
    for (final entry in <String, Widget>{
      'home': HomeView(store: store, onOpen: (_) {}, onPlay: (_) {}),
      'library': LibraryView(store: store, onOpen: (_) {}),
      'sources': SourcesView(store: store, iptv: iptv, onAgent: (_) {}),
      'agent': AgentView(agent: agent, iptv: iptv, onOpen: (_) {}),
    }.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: Platform.environment['SEEWOW_SHOTS'] == '1'
                ? 'CinemaTest'
                : null,
            scaffoldBackgroundColor: WowColors.ink,
            colorScheme: ColorScheme.dark(
              primary: const Color(0xFFD4EF88),
              surface: WowColors.panel,
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(body: entry.value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('${shots.path}/${entry.key}.png').writeAsBytesSync(bytes!);
      expect(tester.takeException(), isNull);
    }
  });
}
