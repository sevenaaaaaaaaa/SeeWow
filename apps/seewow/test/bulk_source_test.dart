import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/sources/bulk_source.dart';

MediaSource _source(String id, String name, {bool enabled = true}) => MediaSource(
  id: id,
  kind: SourceKind.webdav,
  name: name,
  location: 'https://$id.test/dav',
  enabled: enabled,
);

void main() {
  group('多行粘贴整理', () {
    test('去空行、去注释、保序去重', () {
      final entries = bulkEntries('''
https://a.test/dav
# 这行是注释
https://a.test/dav/
// 也是注释

https://b.test/dav
''');
      expect(entries, ['https://a.test/dav', 'https://b.test/dav']);
    });

    test('名称,地址 / 名称 地址 取最后一个像地址的部分', () {
      expect(
        bulkEntries('客厅 NAS, https://nas.test/dav\n卧室 webdav smb://x/y'),
        ['https://nas.test/dav', 'smb://x/y'],
      );
    });

    test('webOnly 只留 http(s)，其它丢掉', () {
      final entries = bulkEntries(
        'ftp://a.test\nhttps://ok.test/dav\n/Users/me/Movies',
        webOnly: true,
      );
      expect(entries, ['https://ok.test/dav']);
    });

    test('本地路径保留', () {
      final entries = bulkEntries('/Users/me/Movies\n/Volumes/NAS/TV');
      expect(entries, ['/Users/me/Movies', '/Volumes/NAS/TV']);
    });
  });

  group('批量操作', () {
    late Directory dir;
    late LibraryStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('seewow-bulk-');
      store = LibraryStore(directory: dir);
      store.sources.addAll([
        _source('a', '甲'),
        _source('b', '乙'),
        _source('c', '丙', enabled: false),
      ]);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('批量停用与启用只动到勾选的', () async {
      final changed = await store.setEnabledMany([store.sources[0], store.sources[1]], false);
      expect(changed, 2);
      expect(store.sources.where((s) => !s.enabled).length, 3);
      final back = await store.setEnabledMany([store.sources[0]], true);
      expect(back, 1);
      expect(store.sources.first.enabled, isTrue);
    });

    test('批量重新扫描：一个失败不影响其它，失败原因带来源名', () async {
      store.scanner = (source) async {
        if (source.id == 'b') throw const FormatException('连不上');
        return <MediaItem>[];
      };
      final report = await store.refreshMany(store.sources);
      expect(report.ok, 2);
      expect(report.failed.keys, ['乙']);
    });

    test('批量断开只移出清单，不碰条目来源以外的东西', () async {
      final removed = await store.removeMany([
        store.sources[0],
        store.sources[2],
      ]);
      expect(removed, 2);
      expect(store.sources.map((s) => s.id), ['b']);
    });
  });
}
