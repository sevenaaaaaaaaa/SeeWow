import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/downloads/download_task.dart';
import 'package:seewow/downloads/downloads_view.dart';

DownloadTask _task(String id, String path, {String title = 'Demo'}) =>
    DownloadTask(
      id: id,
      itemId: 'item-$id',
      title: title,
      sourceName: 'Plex',
      sourceId: 'plex-1',
      filePath: path,
      totalBytes: 3,
      downloadedBytes: 3,
      status: DownloadStatus.completed,
    );

void main() {
  late Directory dir;
  late DownloadManager manager;
  late String existingPath;

  setUp(() async {
    WowSkin.I.reset();
    dir = await Directory.systemTemp.createTemp('seewow-downloads-page-');
    manager = DownloadManager(directory: dir, storageDirectory: dir);
    // Real file I/O must happen outside the fake-async widget test body.
    existingPath = '${dir.path}/here.mp4';
    File(existingPath).writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() async {
    manager.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {double width = 1440}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: DownloadsPage(manager: manager, onPlay: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a task whose file vanished says so and offers no play', (
    tester,
  ) async {
    manager.tasks.add(_task('t1', '${dir.path}/gone.mp4', title: 'Gone'));
    await mount(tester);
    expect(find.text('文件已丢失'), findsOneWidget);
    expect(find.text('离线播放'), findsNothing);
    expect(find.textContaining('不会自动回落到联网播放'), findsOneWidget);
  });

  testWidgets('a real file offers offline playback', (tester) async {
    manager.tasks.add(_task('t2', existingPath, title: 'Here'));
    await mount(tester);
    expect(find.text('文件已丢失'), findsNothing);
    expect(find.text('离线播放'), findsOneWidget);
  });
}
