import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/stream_cache.dart';

/// 在线播放的第二段慢：播放中卡顿、拖动后重下。这条测试钉住「分片落盘 +
/// 30 秒前向缓冲」的配置与清理规则；真机上快多少只能实测，配置本身必须确定。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('seewow-stream-cache-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('磁盘缓存与前向缓冲参数齐全', () async {
    final dir = await StreamCache.prepare(root: root);
    expect(dir, isNotNull);
    final props = StreamCache.properties(directory: dir!);
    expect(props['cache-on-disk'], 'yes');
    expect(props['cache-dir'], dir.path);
    expect(props['demuxer-readahead-secs'], '30');
    expect(props['cache-secs'], '30');
    expect(int.parse(props['demuxer-max-bytes']!), greaterThanOrEqualTo(64 << 20));
  });

  test('超过上限先删最久没动过的文件', () async {
    final a = File('${root.path}/a.ts')..writeAsBytesSync(List.filled(600, 0));
    final b = File('${root.path}/b.ts')..writeAsBytesSync(List.filled(600, 0));
    final c = File('${root.path}/c.ts')..writeAsBytesSync(List.filled(600, 0));
    a.setLastModifiedSync(DateTime(2026, 1, 1));
    b.setLastModifiedSync(DateTime(2026, 1, 2));
    c.setLastModifiedSync(DateTime(2026, 1, 3));

    final removed = await StreamCache.trim(root, cap: 600);

    expect(removed, 2);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(c.existsSync(), isTrue, reason: '最新写入的分片要留着');
  });

  test('不是网络地址就不动播放器属性', () async {
    var calls = 0;
    await StreamCache.apply(
      network: false,
      set: (_, _) async => calls++,
      root: root,
    );
    expect(calls, 0);
    expect(StreamCache.isNetwork('/media/dune.mkv'), isFalse);
    expect(StreamCache.isNetwork('https://cdn.test/1.m3u8'), isTrue);
  });

  test('某个键不被引擎认识时继续设下一个', () async {
    final applied = <String>[];
    await StreamCache.apply(
      network: true,
      root: root,
      set: (key, value) async {
        if (key == 'cache-on-disk') throw StateError('unknown property');
        applied.add(key);
      },
    );
    expect(applied, contains('cache-dir'));
    expect(applied, contains('demuxer-readahead-secs'));
    expect(applied, isNot(contains('cache-on-disk')));
  });
}
