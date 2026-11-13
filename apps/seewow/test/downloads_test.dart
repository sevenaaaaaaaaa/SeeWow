import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/downloads/download_task.dart';

Future<void> _waitFor(DownloadManager manager, String id) async {
  for (var i = 0; i < 120; i++) {
    final task = manager.tasks.where((t) => t.id == id).firstOrNull;
    if (task != null && (task.isDone || task.isFailed)) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('download did not finish');
}

MediaItem _item(String locator, {String title = 'Demo Movie'}) => MediaItem(
  id: 'item-1',
  sourceId: 'source-1',
  kind: MediaKind.movie,
  title: title,
  locator: locator,
  container: 'mp4',
);

void main() {
  test('task json roundtrip keeps progress and status', () {
    final task = DownloadTask(
      id: 't1',
      itemId: 'i1',
      title: 'Dune',
      sourceName: 'Plex',
      totalBytes: 2048,
      downloadedBytes: 1024,
      status: DownloadStatus.paused,
    );
    final again = DownloadTask.fromJson(task.toJson());
    expect(again.id, 't1');
    expect(again.status, DownloadStatus.paused);
    expect(again.progress, 0.5);
    expect(again.sourceName, 'Plex');
  });

  test(
    'copies a local file into the cache and exposes an offline path',
    () async {
      final root = await Directory.systemTemp.createTemp('seewow-download-');
      try {
        final source = File('${root.path}/source.mp4');
        await source.writeAsBytes(List<int>.generate(4096, (i) => i % 256));
        final manager = DownloadManager(
          directory: Directory('${root.path}/config'),
          storageDirectory: Directory('${root.path}/cache'),
          resolver: (_) async =>
              ResolvedMedia(_item(Uri.file(source.path).toString()), null),
        );
        await manager.load();
        final task = await manager.enqueue(
          _item(Uri.file(source.path).toString()),
          sourceName: '本地演示',
        );
        expect(task, isNotNull);
        await _waitFor(manager, task!.id);
      await manager.save();
        final finished = manager.tasks.single;
        expect(finished.isDone, isTrue, reason: finished.error);
        final path = manager.pathFor('item-1');
        expect(path, isNotNull);
        expect(await File(path!).length(), 4096);
        expect(manager.hasOffline('item-1'), isTrue);
        expect(finished.title, 'Demo Movie');
        expect(finished.totalBytes, 4096);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('downloads an HLS playlist into a .ts cache file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/playlist.m3u8') {
        response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        response.write(
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n'
          '#EXTINF:1.0,\nseg1.ts\n#EXTINF:1.0,\nseg2.ts\n#EXT-X-ENDLIST\n',
        );
      } else if (request.uri.path == '/seg1.ts') {
        response.add([1, 2, 3]);
      } else if (request.uri.path == '/seg2.ts') {
        response.add([4, 5, 6]);
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
    final root = await Directory.systemTemp.createTemp('seewow-hls-');
    try {
      final url = 'http://127.0.0.1:${server.port}/playlist.m3u8';
      final manager = DownloadManager(
        directory: Directory('${root.path}/config'),
        storageDirectory: Directory('${root.path}/cache'),
        resolver: (_) async => ResolvedMedia(_item(url), null),
      );
      await manager.load();
      final task = await manager.enqueue(_item(url), sourceName: 'Plex');
      await _waitFor(manager, task!.id);
      await manager.save();
      final finished = manager.tasks.single;
      expect(finished.isDone, isTrue, reason: finished.error);
      final path = manager.pathFor('item-1');
      expect(path, endsWith('.ts'));
      expect(await File(path!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(finished.totalBytes, 6);
    } finally {
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });
}
