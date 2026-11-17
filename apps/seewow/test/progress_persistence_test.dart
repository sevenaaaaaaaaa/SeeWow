import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';

MediaItem film(String id, String source) => MediaItem(
  id: id,
  sourceId: source,
  kind: MediaKind.movie,
  title: id,
  locator: '/$source/$id.mkv',
);

void main() {
  late Directory dir;
  late LibraryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-progress-');
    store = LibraryStore(directory: dir);
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });

  test('RM-06 播放进度不再重写整库，flush 后单独落盘并可恢复', () async {
    store.items.add(film('a', 's'));
    await store.save();
    final library = File('${dir.path}/library.json');
    final before = await library.readAsString();

    await store.updatePosition(store.items.single, 123, 600);
    expect(await library.readAsString(), before, reason: '整库不应被重写');
    expect(File('${dir.path}/progress.json').existsSync(), isFalse);

    await store.flushProgress();
    final progress = File('${dir.path}/progress.json');
    expect(progress.existsSync(), isTrue);
    final raw =
        jsonDecode(await progress.readAsString()) as Map<String, dynamic>;
    expect((raw['items'] as Map)['a']['position'], 123);

    final reloaded = LibraryStore(directory: dir);
    await reloaded.load();
    expect(reloaded.items.single.position, 123);
    expect(reloaded.items.single.duration, 600);
    expect(reloaded.taste.lastPlayed.containsKey('a'), isTrue);
    reloaded.dispose();
  });

  test('RM-06 完整 save 取代待写的进度，不重复落盘', () async {
    store.items.add(film('a', 's'));
    await store.updatePosition(store.items.single, 50, 100);
    await store.save();
    expect(File('${dir.path}/progress.json').existsSync(), isFalse);
    final reloaded = LibraryStore(directory: dir);
    await reloaded.load();
    expect(reloaded.items.single.position, 50);
    reloaded.dispose();
  });
}