import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/downloads/download_task.dart';
import 'package:seewow/features/library_view.dart';

void main() {
  group('已缓存筛选', () {
    late Directory dir;
    late LibraryStore store;
    late DownloadManager downloads;
    late String cachedPath;

    setUp(() async {
      WowSkin.I.reset();
      dir = await Directory.systemTemp.createTemp('seewow-offline-filter-');
      store = LibraryStore(directory: dir);
      store.items.addAll([
        MediaItem(
          id: 'cached',
          sourceId: 'nas',
          kind: MediaKind.movie,
          title: 'Cached Movie',
          locator: '/media/cached.mp4',
          duration: 6000,
        ),
        MediaItem(
          id: 'remote',
          sourceId: 'nas',
          kind: MediaKind.movie,
          title: 'Streaming Movie',
          locator: '/media/remote.mp4',
          duration: 6000,
        ),
      ]);
      downloads = DownloadManager(directory: dir);
      final file = File('${dir.path}/cached.mp4');
      await file.writeAsBytes([1, 2, 3]);
      cachedPath = file.path;
    });

    tearDown(() async {
      downloads.dispose();
      await dir.delete(recursive: true);
    });

    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWowTheme(),
          home: Scaffold(
            body: LibraryView(
              store: store,
              onOpen: (_) {},
              downloads: downloads,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('chip counts cached works and filters the shelf', (
      tester,
    ) async {
      downloads.tasks.add(
        DownloadTask(
          id: 't1',
          itemId: 'cached',
          title: 'Cached Movie',
          sourceName: '本地',
          filePath: cachedPath,
          totalBytes: 3,
          downloadedBytes: 3,
          status: DownloadStatus.completed,
        ),
      );
      await mount(tester);
      expect(find.text('已缓存 · 1'), findsOneWidget);
      expect(find.text('Streaming Movie'), findsWidgets);
      await tester.tap(find.text('已缓存 · 1'));
      await tester.pumpAndSettle();
      expect(find.text('1 个条目'), findsOneWidget);
      expect(find.text('Cached Movie'), findsWidgets);
      expect(find.text('Streaming Movie'), findsNothing);
    });

    testWidgets('empty cache filter explains how to cache', (tester) async {
      await mount(tester);
      expect(find.text('已缓存 · 0'), findsOneWidget);
      await tester.tap(find.text('已缓存 · 0'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有可离线播放的缓存'), findsOneWidget);
    });

    testWidgets('no downloads manager means no cached chip', (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWowTheme(),
          home: Scaffold(body: LibraryView(store: store, onOpen: (_) {})),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已缓存 · 0'), findsNothing);
    });
  });
}
