import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';

MediaSource local(String id, String path, {bool enabled = true, List<String> folders = const []}) =>
    MediaSource(id: id, kind: SourceKind.local, name: id, location: path, enabled: enabled, folders: folders);

void main() {
  late Directory dir;
  late LibraryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-p0-');
    store = LibraryStore(directory: dir);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('RM-02 子目录落在已添加目录之内时被拒绝', () async {
    await store.addSource(local('a', '/media'));
    await expectLater(store.addSource(local('b', '/media/2024')), throwsStateError);
    expect(store.sources.length, 1);
    expect(store.sources.single.id, 'a');
  });

  test('RM-02 添加父目录时，已有子目录同样被拒绝', () async {
    await store.addSource(local('a', '/media/2024'));
    await expectLater(store.addSource(local('b', '/media')), throwsStateError);
    expect(store.sources.length, 1);
  });

  test('RM-02 路径前缀相同但不是父子目录时不误判', () async {
    await store.addSource(local('a', '/media'));
    await store.addSource(local('b', '/media2'));
    expect(store.sources.length, 2);
  });

  test('RM-03 停用来源后状态持久化，条目与字段保留', () async {
    final source = local('a', '/media', folders: ['3', '4']);
    store.sources.add(source);
    await store.setSourceEnabled(source, false);
    expect(store.sources.single.enabled, isFalse);
    expect(store.sources.single.folders, ['3', '4']);
    final reloaded = LibraryStore(directory: dir);
    await reloaded.load();
    expect(reloaded.sources.single.enabled, isFalse);
    expect(reloaded.sources.single.folders, ['3', '4']);
    await reloaded.setSourceEnabled(reloaded.sources.single, true);
    expect(reloaded.sources.single.enabled, isTrue);
  });

  test('RM-08 copyWith 只改指定字段', () {
    final source = MediaSource(
      id: 's1',
      kind: SourceKind.plex,
      name: 'Plex',
      location: 'http://127.0.0.1:32400',
      username: 'u',
      enabled: false,
      providerId: 'plex',
      rootPath: '/video',
      folders: const ['3'],
    );
    final when = DateTime(2026, 11, 17);
    final next = source.copyWith(lastScan: when);
    expect(next.id, source.id);
    expect(next.kind, SourceKind.plex);
    expect(next.username, 'u');
    expect(next.enabled, isFalse);
    expect(next.providerId, 'plex');
    expect(next.rootPath, '/video');
    expect(next.folders, ['3']);
    expect(next.lastScan, when);
    expect(next.copyWith(folders: const ['9']).folders, ['9']);
  });

  test('RM-08 重扫后来源字段一个不丢', () async {
    final source = MediaSource(
      id: 's2',
      kind: SourceKind.plex,
      name: 'Plex 客厅',
      location: 'http://127.0.0.1:32400',
      username: 'u',
      enabled: false,
      providerId: 'plex',
      rootPath: '/video',
      folders: const ['3', '4'],
    );
    store.sources.add(source);
    store.scanner = (_) async => [];
    await store.rescan(source);
    final after = store.sources.single;
    expect(after.username, 'u');
    expect(after.enabled, isFalse);
    expect(after.providerId, 'plex');
    expect(after.rootPath, '/video');
    expect(after.folders, ['3', '4']);
    expect(after.lastScan, isNotNull);
  });
}