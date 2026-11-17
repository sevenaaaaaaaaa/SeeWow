import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/sources_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late LibraryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-actions-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => dir.path);
    store = LibraryStore(directory: dir);
    store.sources.add(
      MediaSource(
        id: 'src1',
        kind: SourceKind.local,
        name: '电影',
        location: '/media',
      ),
    );
    store.items.add(
      MediaItem(
        id: 'i1',
        sourceId: 'src1',
        kind: MediaKind.movie,
        title: '片一',
        locator: '/media/i1.mkv',
      ),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SourcesView(store: store, iptv: IPTVStore(), onAgent: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('片源操作'));
    await tester.pumpAndSettle();
  }

  testWidgets('RM-01 断开来源先确认，取消不动数据', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('片源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开来源（不删除文件）'));
    await tester.pumpAndSettle();
    expect(find.text('断开这个来源？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('1 个条目'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.sources.length, 1);
    expect(store.items.length, 1);

    await tester.tap(find.byTooltip('片源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开来源（不删除文件）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开来源'));
    await tester.pumpAndSettle();
    expect(store.sources, isEmpty);
    expect(store.items, isEmpty);
  });

  testWidgets('RM-03 菜单可以停用来源，列表显示已停用', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('片源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用来源（不参与刷新）'));
    await tester.pumpAndSettle();
    expect(store.sources.single.enabled, isFalse);
    expect(find.textContaining('已停用'), findsOneWidget);
  });

  testWidgets('扫描失败的行可以直接重试', (tester) async {
    var scans = 0;
    store.sourceErrors['src1'] = '连接超时';
    store.scanner = (_) async {
      scans++;
      return const [];
    };
    await mount(tester);
    expect(find.text('重试'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('重试'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(scans, 1);
    expect(store.sourceErrors.containsKey('src1'), isFalse);
  });
}