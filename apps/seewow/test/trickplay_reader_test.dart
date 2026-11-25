import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/trickplay.dart';

/// 缓存器的读口：拖动时按秒取帧。
///
/// 这一组钉三件事：秒落到哪个桶、越界怎么钳、内存层会不会把不同条目混成一个。

class _FakeSource implements TrickplaySource {
  final List<double> asked = [];
  @override
  Future<void> open(MediaItem item) async {}
  @override
  Future<Uint8List?> grab(double seconds) async {
    asked.add(seconds);
    // 每帧的字节内容带桶号，取出来就能反查是哪一桶
    return Uint8List.fromList([asked.length, 7, 7, 7]);
  }

  @override
  Future<void> close() async {}
}

MediaItem _item(String locator, {double duration = 100}) => MediaItem(
  id: 'demo',
  sourceId: 'local',
  kind: MediaKind.movie,
  title: 'Demo',
  locator: locator,
  duration: duration,
);

void main() {
  late Directory root;
  late TrickplayCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('trickplay-reader');
    cache = TrickplayCache(directory: root);
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('秒 → 桶：27 秒取到的是第 3 桶（20–30 秒）', () async {
    final item = _item('${root.path}/demo.mkv');
    await TrickplayBuilder(cache: cache, openSource: () async => _FakeSource())
        .build(item);

    final frame = await cache.frameAt(item, 27);
    expect(frame, isNotNull);
    expect(frame!.first, 3); // 第 3 次取帧 = 第 3 桶
  });

  test('负数与超大秒数都钳在两端', () async {
    final item = _item('${root.path}/demo.mkv');
    await TrickplayBuilder(cache: cache, openSource: () async => _FakeSource())
        .build(item);
    expect((await cache.frameAt(item, -99))!.first, 1);
    expect((await cache.frameAt(item, 1e6))!.first, 10);
  });

  test('没建过的条目、片长为 0，都返回 null 而不是抛', () async {
    final item = _item('${root.path}/never.mkv');
    expect(await cache.frameAt(item, 12), isNull);
    expect(await cache.frameAt(_item('${root.path}/live.m3u8', duration: 0), 5), isNull);
  });

  test('内存层：命中不重复读盘，且容量到顶就淘汰最旧的', () async {
    final item = _item('${root.path}/demo.mkv');
    await TrickplayBuilder(cache: cache, openSource: () async => _FakeSource())
        .build(item);

    final reader = TrickplayReader(cache: cache, capacity: 2);
    expect((await reader.at(item, 5))!.first, 1);
    expect((await reader.at(item, 15))!.first, 2);
    expect(reader.memoSize, 2);
    expect((await reader.at(item, 25))!.first, 3);
    expect(reader.memoSize, 2, reason: '到顶就该淘汰最旧的一条');

    // 淘汰之后再读第一桶：重新从盘上取，内容仍然正确
    expect((await reader.at(item, 5))!.first, 1);
  });

  test('不同条目不会共用内存槽位', () async {
    final a = _item('${root.path}/a.mkv');
    final b = _item('${root.path}/b.mkv');
    for (final item in [a, b]) {
      await TrickplayBuilder(cache: cache, openSource: () async => _FakeSource())
          .build(item);
    }
    final reader = TrickplayReader(cache: cache);
    expect(reader.memoSize, 0);
    await reader.at(a, 5);
    await reader.at(b, 5);
    expect(reader.memoSize, 2);
  });
}
