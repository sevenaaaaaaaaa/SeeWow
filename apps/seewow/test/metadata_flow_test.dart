import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/features/metadata_dialog.dart';
import 'package:seewow/features/sources_view.dart';
import 'package:seewow/metadata/tmdb_client.dart';

class _FixtureTmdb extends TmdbClient {
  _FixtureTmdb() : super('fixture');
  static const match = MediaMetadata(
    id: 42,
    mediaType: 'movie',
    title: '确认后的电影',
    year: 2024,
    overview: '这是一部用于验证预览后保存流程的影片。',
    genres: ['科幻'],
  );
  @override
  Future<List<MediaMetadata>> search(
    String query, {
    bool series = false,
  }) async => [match];
  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async => match;
}

void main() {
  late Directory dir;
  late LibraryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-metadata-flow-');
    store = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'm',
          sourceId: 's',
          kind: MediaKind.movie,
          title: '原文件名',
          locator: '/movie.mkv',
          position: 123,
          duration: 1000,
        ),
      );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => matchMetadata(
                context,
                store,
                store.items.single,
                clientFactory: () async => _FixtureTmdb(),
              ),
              child: const Text('匹配'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索 TMDB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认后的电影'));
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets(
      'metadata preview fits at $width and cancel leaves library intact',
      (tester) async {
        addTearDown(tester.view.reset);
        await open(tester, width);
        expect(store.items.single.title, '原文件名');
        expect(store.items.single.metadata, isNull);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(store.items.single.title, '原文件名');
      },
    );
  }
  testWidgets('only explicit confirmation applies the reviewed metadata', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await open(tester, 768);
    await tester.runAsync(() async {
      await tester.tap(find.text('确认匹配并保存'));
      await store.save();
    });
    await tester.pumpAndSettle();
    expect(store.items.single.title, '确认后的电影');
    expect(store.items.single.position, 123);
    expect(store.items.single.locator, '/movie.mkv');
    expect(find.text('匹配影片信息'), findsNothing);
  });
  testWidgets(
    'server connection validates API key before starting import on a phone',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => connectSource(
                  context,
                  store,
                  IPTVStore(),
                  type: 'jellyfin',
                ),
                child: const Text('连接服务器'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('连接服务器'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'http://127.0.0.1:8096',
      );
      await tester.tap(find.text('测试连接并导入'));
      await tester.pumpAndSettle();
      expect(find.text('请输入服务器 API Key'), findsOneWidget);
      expect(store.sources, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
