import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/trickplay.dart';

/// 假取帧器：不碰视频，只记账。缓存层的正确性（索引、断点、过期、失败上限）
/// 全在这里验；真机取帧是另一个问题，见 trickplay_media_kit.dart。
class _FakeSource implements TrickplaySource {
  _FakeSource({this.alwaysNull = false});

  final bool alwaysNull;
  final List<double> asked = [];
  int opens = 0;
  bool closed = false;

  @override
  Future<void> open(MediaItem item) async {
    opens++;
  }

  @override
  Future<Uint8List?> grab(double seconds) async {
    asked.add(seconds);
    if (alwaysNull) return null;
    return Uint8List.fromList(List<int>.filled(64, asked.length % 256));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
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
    root = Directory.systemTemp.createTempSync('trickplay-test');
    cache = TrickplayCache(directory: root);
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('时间与桶', () {
    test('2 小时片是 720 个桶；0 秒片是 0', () {
      expect(TrickplayCache.totalFor(7200), 720);
      expect(TrickplayCache.totalFor(100), 10);
      expect(TrickplayCache.totalFor(0), 0);
      expect(TrickplayCache.totalFor(-5), 0);
    });

    test('秒数落桶，越界钳到两端', () {
      expect(TrickplayCache.indexFor(0, 100), 0);
      expect(TrickplayCache.indexFor(9.99, 100), 0);
      expect(TrickplayCache.indexFor(10, 100), 1);
      expect(TrickplayCache.indexFor(-3, 100), 0);
      expect(TrickplayCache.indexFor(9999, 100), 9);
    });

    test('采样点取桶中心，最后一桶不越片尾', () {
      expect(TrickplayCache.timeForIndex(0, 100), 5);
      expect(TrickplayCache.timeForIndex(9, 100), 95);
      expect(TrickplayCache.timeForIndex(9, 95), closeTo(94.95, 1e-9));
    });
  });

  test('条目标识只看身份：同一个片子两次相同，换定位符就变', () {
    final a = cache.keyFor(_item('/x/a.mkv'));
    final b = cache.keyFor(_item('/x/a.mkv'));
    final c = cache.keyFor(_item('/x/b.mkv'));
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 16);
    expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(a), isTrue);
  });

  test('构建：写清单 + 每桶一帧，状态 ready', () async {
    final item = _item('${root.path}/demo.mkv');
    final source = _FakeSource();
    final builder = TrickplayBuilder(cache: cache, openSource: () async => source);

    final result = await builder.build(item);

    expect(result.state, 'ready');
    expect(result.written, 10);
    expect(result.missing, 0);
    expect(source.opens, 1);
    expect(source.closed, isTrue);
    // 采样点就是桶中心，一个不多一个不少
    expect(source.asked, [5, 15, 25, 35, 45, 55, 65, 75, 85, 95]);

    final manifest = await cache.read(cache.keyFor(item));
    expect(manifest, isNotNull);
    expect(manifest!.format, kTrickplayFormat);
    expect(manifest.interval, 10);
    expect(manifest.width, 160);
    expect(manifest.total, 10);
    expect(manifest.done, 10);
    expect(manifest.state, 'ready');

    final frame = await cache.frameFile(cache.keyFor(item), 3);
    expect(await frame.exists(), isTrue);
    expect(await frame.length(), 64);
  });

  test('断点续建：只补缺的，不重跑已完成的', () async {
    final item = _item('${root.path}/demo.mkv');
    await TrickplayBuilder(
      cache: cache,
      openSource: () async => _FakeSource(),
    ).build(item);

    final key = cache.keyFor(item);
    for (final index in [2, 7]) {
      await (await cache.frameFile(key, index)).delete();
    }

    final second = _FakeSource();
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async => second,
    ).build(item);

    expect(second.asked, [25, 75]);
    expect(result.written, 2);
    expect(result.reused, 8);
    expect(result.state, 'ready');
  });

  test('时长变了就整条重建', () async {
    final item = _item('${root.path}/demo.mkv');
    await TrickplayBuilder(
      cache: cache,
      openSource: () async => _FakeSource(),
    ).build(item);

    final longer = _item('${root.path}/demo.mkv', duration: 200);
    final second = _FakeSource();
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async => second,
    ).build(longer);

    expect(second.asked.length, 20);
    expect(result.written, 20);
    expect(result.state, 'ready');
  });

  test('源文件变了（体积）也重建', () async {
    final file = File('${root.path}/real.mkv')..writeAsBytesSync([1, 2, 3]);
    final item = _item(file.path);
    await TrickplayBuilder(
      cache: cache,
      openSource: () async => _FakeSource(),
    ).build(item);

    file.writeAsBytesSync(List<int>.filled(9999, 7));
    final second = _FakeSource();
    await TrickplayBuilder(
      cache: cache,
      openSource: () async => second,
    ).build(item);

    expect(second.asked.length, 10);
  });

  test('清单损坏当成没有，不抛给调用方', () async {
    final item = _item('${root.path}/demo.mkv');
    final key = cache.keyFor(item);
    await cache.dirFor(key);
    File('${root.path}/$key/index.json').writeAsStringSync('{ not json');

    expect(await cache.read(key), isNull);
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async => _FakeSource(),
    ).build(item);
    expect(result.state, 'ready');
  });

  test('格式版本不符一律当过期', () async {
    final item = _item('${root.path}/demo.mkv');
    final key = cache.keyFor(item);
    await cache.writeManifest(
      TrickplayManifest(
        format: kTrickplayFormat + 1,
        key: key,
        interval: kTrickplayInterval,
        width: kTrickplayWidth,
        duration: 100,
        total: 10,
        done: 10,
        missing: 0,
        state: 'ready',
        sourceSize: 0,
        sourceMtimeMs: 0,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    expect(await cache.read(key), isNull);

    final second = _FakeSource();
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async => second,
    ).build(item);
    expect(second.asked.length, 10);
    expect(result.state, 'ready');
  });

  test('取不到帧：失败到上限就停，标 failed，不无限重试', () async {
    final item = _item('${root.path}/demo.mkv');
    final source = _FakeSource(alwaysNull: true);
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async => source,
    ).build(item);

    expect(result.state, 'failed');
    expect(result.written, 0);
    expect(source.asked.length, TrickplayBuilder.failureLimit);
  });

  test('中途中断：已写的留着，续建接着补', () async {
    final item = _item('${root.path}/demo.mkv');
    final key = cache.keyFor(item);
    var asked = 0;
    final result = await TrickplayBuilder(cache: cache, openSource: () async {
      return _StopAfter(3, () => asked++);
    }).build(item, isCancelled: () => asked >= 3);

    expect(result.state, 'building');
    expect(result.written, 3);
    final frames = await cache.existingFrames(key);
    expect(frames.length, 3);

    final rest = _FakeSource();
    final done = await TrickplayBuilder(
      cache: cache,
      openSource: () async => rest,
    ).build(item);
    expect(done.state, 'ready');
    expect(rest.asked.length, 7);
    expect((await cache.existingFrames(key)).length, 10);
  });

  test('队列：同一个条目排两次，只跑一次', () async {
    final item = _item('${root.path}/demo.mkv');
    final queue = TrickplayQueue(cache: cache);
    var opens = 0;

    final a = queue.start(item, () {
      opens++;
      return _FakeSource();
    });
    final b = queue.start(item, () {
      opens++;
      return _FakeSource();
    });
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(opens, 1);
    expect(queue.pending, 0);
  });

  test('时长未知（0）直接跳过，不开播放器', () async {
    var opened = false;
    final result = await TrickplayBuilder(
      cache: cache,
      openSource: () async {
        opened = true;
        return _FakeSource();
      },
    ).build(_item('${root.path}/live.m3u8', duration: 0));
    expect(result.state, 'skipped');
    expect(opened, isFalse);
  });
}

class _StopAfter implements TrickplaySource {
  _StopAfter(this.limit, this.onGrab);
  final int limit;
  final void Function() onGrab;
  final List<double> asked = [];
  @override
  Future<void> open(MediaItem item) async {}
  @override
  Future<Uint8List?> grab(double seconds) async {
    onGrab();
    asked.add(seconds);
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> close() async {}
}
