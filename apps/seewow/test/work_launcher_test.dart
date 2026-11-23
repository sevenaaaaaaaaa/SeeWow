import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/playback/work_launcher.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';
import 'package:seewow/sources/work_aggregator.dart';

OnlineSite _site(String id, String name) =>
    OnlineSite(id: id, name: name, api: 'https://$id.test/api.php/provide/vod');

CmsVodItem _item(
  String name, {
  String year = '2024',
  bool direct = true,
  int episodes = 2,
}) => CmsVodItem(
  id: '$name-$year',
  name: name,
  year: year,
  remarks: direct ? 'HD1080P' : '更新至$episodes集',
  playFrom: 'lzm3u8',
  playUrl: [
    for (var i = 1; i <= episodes; i++)
      '第0$i集\$${direct ? 'https://cdn.test/$name/$i.m3u8' : 'https://site.test/play/$i'}',
  ].join('#'),
);

Work _work(List<(OnlineSite, CmsVodItem)> hits) {
  final works = WorkAggregator().group([
    for (final (site, item) in hits) OnlineSearchHit(site, item),
  ]);
  return works.single;
}

void main() {
  test('直连源优先：起播直接给第 1 集的地址', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片', direct: false)),
      (_site('b', 'B站'), _item('某片')),
    ]);
    final result = await WorkLauncher().launch(work);
    expect(result.ok, isTrue);
    expect(result.source!.siteName, 'B站');
    expect(result.item!.locator, contains('.m3u8'));
    expect(result.episodeName, '第01集');
  });

  test('地址解析失败自动换下一个源，并说清为什么', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片')),
      (_site('b', 'B站'), _item('某片')),
    ]);
    final skipped = <String>[];
    final result = await WorkLauncher().launch(
      work,
      prepare: (item) async {
        if (item.sourceId.contains('online-a')) {
          throw const FormatException('连接超时');
        }
        return item;
      },
      onSkip: skipped.add,
    );

    expect(result.ok, isTrue);
    expect(result.source!.siteName, 'B站');
    expect(skipped.single, contains('A站'));
    // 失败记录要在结果里如实带上，界面才能解释发生了什么。
    expect(result.reasons.single, contains('连接超时'));
  });

  test('失败过的源下次排到最后，不重复踩坑', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片')),
      (_site('b', 'B站'), _item('某片')),
    ]);
    final launcher = WorkLauncher();
    final first = await launcher.launch(
      work,
      prepare: (item) async {
        if (item.sourceId.contains('online-a')) {
          throw const FormatException('连接超时');
        }
        return item;
      },
    );
    expect(first.source!.siteName, 'B站');
    expect(launcher.ranked(work).first.siteName, 'B站');
    expect(launcher.hasFailed(work, work.sources.first), isTrue);

    // 第二次起播，第一个尝试的就该是上次成功的那个源。
    final second = await launcher.launch(work);
    expect(second.source!.siteName, 'B站');
  });

  test('全部源只有分享页：明确失败，不假装能播', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片', direct: false)),
      (_site('b', 'B站'), _item('某片', direct: false)),
    ]);
    final result = await WorkLauncher().launch(work);
    expect(result.ok, isFalse);
    expect(result.summary, contains('没有可直连'));
  });

  test('最多只试 maxAttempts 个源', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片')),
      (_site('b', 'B站'), _item('某片')),
      (_site('c', 'C站'), _item('某片')),
      (_site('d', 'D站'), _item('某片')),
    ]);
    var attempts = 0;
    final result = await WorkLauncher(maxAttempts: 2).launch(
      work,
      prepare: (item) async {
        attempts++;
        throw const FormatException('全坏');
      },
    );
    expect(result.ok, isFalse);
    expect(attempts, 2);
  });

  test('造出来的条目带 Referer 与 UA，播放器不需要另外处理', () async {
    final work = _work([(_site('a', 'A站'), _item('某片'))]);
    final result = await WorkLauncher().launch(work);
    final item = result.item!;
    expect(item.httpHeaders['Referer'], 'https://a.test');
    expect(item.httpHeaders['User-Agent'], 'okhttp/3.15');
    expect(item.kind, MediaKind.episode);
    expect(item.showTitle, '某片');
  });

  test('指定 prefer 时从那个源起播', () async {
    final work = _work([
      (_site('a', 'A站'), _item('某片')),
      (_site('b', 'B站'), _item('某片')),
    ]);
    final launcher = WorkLauncher();
    final result = await launcher.launch(work, prefer: work.sources.last);
    expect(result.source!.siteName, work.sources.last.siteName);
  });
}
