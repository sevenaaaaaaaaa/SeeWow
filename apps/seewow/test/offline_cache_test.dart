import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/downloads/download_task.dart';

MediaItem _item(String id, String title, {String sourceId = 'plex-1'}) =>
    MediaItem(
      id: id,
      sourceId: sourceId,
      kind: MediaKind.movie,
      title: title,
      locator: '/remote/$id.mkv',
    );

DownloadTask _task({
  required String id,
  required String itemId,
  required String title,
  required String filePath,
  String sourceId = 'plex-1',
  DownloadStatus status = DownloadStatus.completed,
}) => DownloadTask(
  id: id,
  itemId: itemId,
  title: title,
  sourceName: 'Plex',
  sourceId: sourceId,
  filePath: filePath,
  totalBytes: 3,
  downloadedBytes: 3,
  status: status,
);

void main() {
  late Directory dir;
  late DownloadManager manager;
  late String cachedPath;
  late String missingPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-offline-');
    manager = DownloadManager(directory: dir);
    cachedPath = '${dir.path}/cached.mp4';
    await File(cachedPath).writeAsBytes([1, 2, 3]);
    missingPath = '${dir.path}/gone.mp4';
  });

  tearDown(() async {
    manager.dispose();
    await dir.delete(recursive: true);
  });

  test('a re-linked source still matches by title', () {
    // Plex was re-added: library ids changed, the downloaded file did not.
    manager.tasks.add(
      _task(
        id: 't1',
        itemId: 'old-source:101',
        title: '夜航',
        filePath: cachedPath,
      ),
    );
    final item = _item('new-source:101', '夜航', sourceId: 'plex-2');
    expect(manager.isCached(item), isTrue);
    expect(manager.cachedItemIds([item]), {'new-source:101'});
    expect(manager.pathFor(item.id), isNull); // exact id only
  });

  test('status is not trusted: a file on disk is playable', () {
    manager.tasks.add(
      _task(
        id: 't2',
        itemId: 'plex-1:102',
        title: 'Failed But Here',
        filePath: cachedPath,
        status: DownloadStatus.failed,
      ),
    );
    final item = _item('plex-1:102', 'Failed But Here');
    expect(manager.isCached(item), isTrue);
    expect(manager.pathFor(item.id), cachedPath);
  });

  test('a completed task whose file vanished is not cached', () {
    manager.tasks.add(
      _task(
        id: 't3',
        itemId: 'plex-1:103',
        title: 'Gone Movie',
        filePath: missingPath,
      ),
    );
    final item = _item('plex-1:103', 'Gone Movie');
    expect(manager.isCached(item), isFalse);
    expect(manager.cachedItemIds([item]), isEmpty);
    expect(manager.pathFor(item.id), isNull);
  });

  test('pathFor uses the task that actually has a file', () {
    manager.tasks.addAll([
      _task(
        id: 't4',
        itemId: 'plex-1:104',
        title: 'Retried Movie',
        filePath: missingPath,
        status: DownloadStatus.failed,
      ),
      _task(
        id: 't5',
        itemId: 'plex-1:104',
        title: 'Retried Movie',
        filePath: cachedPath,
      ),
    ]);
    expect(manager.pathFor('plex-1:104'), cachedPath);
  });

  test('CJK titles survive normalization', () {
    manager.tasks.add(
      _task(
        id: 't6',
        itemId: 'x:1',
        title: '夜航 2020（导演剪辑版）',
        filePath: cachedPath,
      ),
    );
    final item = _item('y:1', '夜航 2020 (导演剪辑版)', sourceId: 'plex-9');
    expect(manager.isCached(item), isTrue);
  });
}
