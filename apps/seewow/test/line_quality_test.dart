import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/playback/line_quality.dart';
import 'package:seewow/playback/work_launcher.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';
import 'package:seewow/sources/work_aggregator.dart';

OnlineSite _site(String id, String name) =>
    OnlineSite(id: id, name: name, api: 'https://$id.test/api.php/provide/vod');

CmsVodItem _item(String name, String host) => CmsVodItem(
  id: '$name-2024',
  name: name,
  year: '2024',
  remarks: 'HD1080P',
  playFrom: 'lzm3u8',
  playUrl: '第01集\$https://$host/$name/1.m3u8',
);

Work _work(List<(OnlineSite, CmsVodItem)> hits) => WorkAggregator().group([
  for (final (site, item) in hits) OnlineSearchHit(site, item),
]).single;

class _FakeProbe implements LineProbe {
  _FakeProbe(this.millisByHost);

  final Map<String, int?> millisByHost;
  int calls = 0;

  @override
  Future<int?> measure(
    MediaItem item, {
    Duration budget = const Duration(milliseconds: 1400),
  }) async {
    calls++;
    return millisByHost[Uri.parse(item.locator).host];
  }
}

void main() {
  late Directory dir;
  late LineMemory memory;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-line-');
    memory = LineMemory(directory: dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Work threeSources() => _work([
    (_site('a', 'A站'), _item('某片', 'cdn-a.test')),
    (_site('b', 'B站'), _item('某片', 'cdn-b.test')),
    (_site('c', 'C站'), _item('某片', 'cdn-c.test')),
  ]);

  test('按实测首包时间选线路，不按站点排序赌', () async {
    final work = threeSources();
    final probe = _FakeProbe({
      'cdn-a.test': 300,
      'cdn-b.test': 60,
      'cdn-c.test': 800,
    });
    final result = await WorkLauncher(
      probe: probe,
      memory: memory,
    ).launch(work);

    expect(result.ok, isTrue);
    expect(result.source!.siteName, 'B站');
    expect(probe.calls, 3, reason: '三条都要测，才能知道哪条快');
    expect(memory.bestSite(work.id), 'b');
  });

  test('测出来的结果会被记住：第二次起播不再测', () async {
    final work = threeSources();
    final probe = _FakeProbe({
      'cdn-a.test': 300,
      'cdn-b.test': 60,
      'cdn-c.test': 800,
    });
    final launcher = WorkLauncher(probe: probe, memory: memory);
    final first = await launcher.launch(work);
    expect(first.source!.siteName, 'B站');
    final callsAfterFirst = probe.calls;

    final second = await launcher.launch(work);
    expect(second.source!.siteName, 'B站');
    expect(probe.calls, callsAfterFirst, reason: '记忆命中就不该再花 1.4 秒重测');
  });

  test('最快的那条打不开时换下一条，并把记忆作废', () async {
    final work = threeSources();
    final probe = _FakeProbe({
      'cdn-a.test': 40,
      'cdn-b.test': 200,
      'cdn-c.test': 400,
    });
    final result = await WorkLauncher(probe: probe, memory: memory).launch(
      work,
      prepare: (item) async {
        if (item.sourceId.contains('online-a')) {
          throw const FormatException('连接超时');
        }
        return item;
      },
    );

    expect(result.ok, isTrue);
    expect(result.source!.siteName, isNot('A站'));
    expect(memory.bestSite(work.id), isNot('a'), reason: '坏线路的记忆要删掉，下次重新测');
  });

  test('记忆会落盘，换一个实例仍然知道哪条快', () async {
    await memory.ensureLoaded();
    await memory.record('w1', 'b', 120);
    final reopened = LineMemory(directory: dir);
    await reopened.ensureLoaded();
    expect(reopened.bestSite('w1'), 'b');
  });

  test('没有探针时行为不变：按原排序直接起播', () async {
    final probe = _FakeProbe({'cdn-a.test': 10});
    final result = await WorkLauncher().launch(threeSources());
    expect(result.ok, isTrue);
    expect(probe.calls, 0);
  });
}
