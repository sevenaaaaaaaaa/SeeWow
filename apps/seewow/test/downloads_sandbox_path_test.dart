import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/downloads/sandbox_path.dart';

/// 现场还原：iOS 应用容器 UUID 在升级后换掉，但文件本体还在新容器的同
/// 一相对路径下。存下来的绝对路径失效，不该被当成「文件已删除」。
void main() {
  group('容器路径换算', () {
    test('取容器根之后的部分', () {
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/SeeWow/a.mp4';
      expect(sandboxSuffix(stored), 'Documents/SeeWow/a.mp4');
    });

    test('不是容器路径就不动', () {
      expect(sandboxSuffix('/Users/me/Movies/a.mp4'), isNull);
      expect(sandboxSuffix(''), isNull);
    });
  });

  group('加载时重挂旧容器路径', () {
    late Directory root;
    late Directory config;
    late Directory oldContainer;
    late Directory newContainer;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('seewow-sandbox-');
      config = Directory('${root.path}/config')..createSync(recursive: true);
      oldContainer = Directory('${root.path}/A')..createSync(recursive: true);
      newContainer = Directory('${root.path}/B')
        ..createSync(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    String storedPath(Directory container) =>
        '/var/mobile/Containers/Data/Application/${container.path.split('/').last}'
        '/Documents/SeeWow/film.mp4';

    Future<void> seed(String path, {String status = 'completed'}) async {
      await File('${config.path}/downloads.json').writeAsString(
        jsonEncode({
          'storagePath': null,
          'speedLimitKbps': 0,
          'tasks': [
            {
              'id': 't1',
              'itemId': 'plex-1',
              'title': '测试片',
              'sourceName': 'Plex',
              'sourceId': 'plex-home',
              'quality': '原始画质',
              'qualityId': 'original',
              'filePath': path,
              'totalBytes': 100,
              'downloadedBytes': 100,
              'status': status,
              'createdAt': DateTime(2026, 1, 1).toIso8601String(),
              'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
            },
          ],
        }),
      );
    }

    DownloadManager manager({Directory? storage}) => DownloadManager(
      directory: config,
      storageDirectory: storage,
      relocator: (stored) =>
          relocateSandboxPath(stored, containerRoot: newContainer),
    );

    test('文件在新容器里 → 重挂成功，仍然可播，路径写回', () async {
      final dir = Directory('${newContainer.path}/Documents/SeeWow')
        ..createSync(recursive: true);
      File('${dir.path}/film.mp4').writeAsBytesSync([1, 2, 3]);
      await seed(storedPath(oldContainer));

      final downloads = manager();
      await downloads.load();

      expect(downloads.playableTasks.length, 1);
      expect(
        downloads.pathFor('plex-1'),
        '${newContainer.path}/Documents/SeeWow/film.mp4',
      );
      final saved =
          jsonDecode(await File('${config.path}/downloads.json').readAsString())
              as Map<String, dynamic>;
      expect(
        (saved['tasks'] as List).single['filePath'],
        '${newContainer.path}/Documents/SeeWow/film.mp4',
      );
    });

    test('新容器里也没有 → 保持缺失，不假装能播', () async {
      await seed(storedPath(oldContainer));
      final downloads = manager();
      await downloads.load();
      expect(downloads.playableTasks, isEmpty);
      expect(downloads.pathFor('plex-1'), isNull);
    });

    test('容器路径形状也变了 → 按文件名在下载目录里唯一匹配', () async {
      final storage = Directory('${newContainer.path}/Movies/SeeWow')
        ..createSync(recursive: true);
      final file = File('${storage.path}/film.mp4')
        ..writeAsBytesSync([9]);
      await seed('/completely/different/place/film.mp4');

      final downloads = manager(storage: storage);
      await downloads.load();
      expect(downloads.pathFor('plex-1'), file.path);
    });

    test('下载目录里有同名两份 → 宁可不认，也不张冠李戴', () async {
      final storage = Directory('${newContainer.path}/Movies/SeeWow')
        ..createSync(recursive: true);
      Directory('${storage.path}/a').createSync(recursive: true);
      Directory('${storage.path}/b').createSync(recursive: true);
      File('${storage.path}/a/film.mp4').writeAsBytesSync([1]);
      File('${storage.path}/b/film.mp4').writeAsBytesSync([2]);
      await seed('/completely/different/place/film.mp4');

      final downloads = manager(storage: storage);
      await downloads.load();
      expect(downloads.playableTasks, isEmpty);
    });

    test('存储目录也过期时一起重挂', () async {
      final dir = Directory('${newContainer.path}/Documents/SeeWow')
        ..createSync(recursive: true);
      File('${dir.path}/film.mp4').writeAsBytesSync([1]);
      await File('${config.path}/downloads.json').writeAsString(
        jsonEncode({
          'storagePath': storedPath(oldContainer).replaceAll('/film.mp4', ''),
          'speedLimitKbps': 0,
          'tasks': <Object>[],
        }),
      );
      final downloads = manager();
      await downloads.load();
      expect(downloads.storagePath, '${newContainer.path}/Documents/SeeWow');
    });
  });
}
