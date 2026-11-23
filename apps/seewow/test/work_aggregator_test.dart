import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';
import 'package:seewow/sources/work_aggregator.dart';

OnlineSite _site(String id, String name) =>
    OnlineSite(id: id, name: name, api: 'https://$id.test/api.php/provide/vod');

CmsVodItem _item(
  String name, {
  String year = '',
  String remarks = '',
  String pic = '',
  int episodes = 2,
  bool direct = true,
}) {
  final urls = [
    for (var i = 1; i <= episodes; i++)
      '第0$i集\$${direct ? 'https://cdn.test/$name/$i.m3u8' : 'https://site.test/play/$i'}',
  ].join('#');
  return CmsVodItem(
    id: '$name-$year',
    name: name,
    year: year,
    remarks: remarks,
    pic: pic,
    playFrom: 'lzm3u8',
    playUrl: urls,
  );
}

OnlineSearchHit _hit(OnlineSite site, CmsVodItem item) =>
    OnlineSearchHit(site, item);

MediaItem _local(String title, {String? show}) => MediaItem(
  id: 'local-$title',
  sourceId: 'src',
  kind: MediaKind.episode,
  title: title,
  showTitle: show,
  locator: '/media/$title.mkv',
);

void main() {
  test('同一部片在 4 个站 = 1 行，源按「直连 + 清晰度」排序', () {
    final hits = [
      _hit(_site('a', 'A站'), _item('流浪地球', year: '2019', remarks: 'HD')),
      _hit(_site('b', 'B站'), _item('流浪地球', year: '2019', remarks: 'HD1080P')),
      _hit(_site('c', 'C站'), _item('流浪地球', year: '2019', remarks: '4K')),
      _hit(
        _site('d', 'D站'),
        _item('流浪地球', year: '2019', remarks: '更新至2集', direct: false),
      ),
    ];
    final works = WorkAggregator().group(hits);
    expect(works.length, 1);
    final work = works.first;
    expect(work.title, '流浪地球');
    expect(work.sources.length, 4);
    expect(work.siteCount, 4);
    // 4K 直连排第一，需解析的排最后。
    expect(work.sources.first.siteName, 'C站');
    expect(work.sources.first.quality, '4K');
    expect(work.sources.last.siteName, 'D站');
    expect(work.sources.last.directPlay, isFalse);
    expect(work.hasDirectSource, isTrue);
    expect(work.headline, contains('可直连'));
    expect(work.headline, contains('4K'));
    expect(work.headline, contains('4 个源'));
  });

  test('同一站把同一部片吐两次：只留一行', () {
    final site = _site('a', 'A站');
    final hits = [
      _hit(site, _item('庆余年', year: '2019', episodes: 4)),
      // 同一个条目 id（_item 用「片名-年份」做 id），集数不同。
      _hit(site, _item('庆余年', year: '2019', episodes: 9)),
    ];
    final work = WorkAggregator().group(hits).single;
    expect(work.sources.length, 1);
    expect(work.sources.single.episodeCount, 9, reason: '同条目留集数多的那份');
  });

  test('同站同片、条目 id 不同（不同分类各吐一次）也只留一行', () {
    final site = _site('a', 'A站');
    // 两条记录的 id 不同：CmsVodItem 的 id 在测试里由片名+年份+集数决定，
    // 这里手工造出「同片不同 id」的情形。
    final first = CmsVodItem(
      id: 'cat1-1', name: '庆余年', year: '2019', remarks: 'HD',
      playFrom: 'lzm3u8', playUrl: '第01集\$https://cdn.test/1.m3u8',
    );
    final second = CmsVodItem(
      id: 'cat2-9', name: '庆余年', year: '2019', remarks: 'HD1080P',
      playFrom: 'lzm3u8',
      playUrl: '第01集\$https://cdn.test/1.m3u8#第02集\$https://cdn.test/2.m3u8',
    );
    final work = WorkAggregator()
        .group([_hit(site, first), _hit(site, second)])
        .single;
    expect(work.sources.length, 1);
    expect(work.sources.single.quality, '1080P', reason: '留清晰度更高的那份');
    expect(work.sources.single.episodeCount, 2);
  });

  test('年份不同就是两部片，不能被并成一行', () {
    final hits = [
      _hit(_site('a', 'A站'), _item('流浪地球', year: '2019')),
      _hit(_site('a', 'A站'), _item('流浪地球', year: '2027')),
    ];
    final works = WorkAggregator().group(hits);
    expect(works.length, 2);
    expect(works.map((w) => w.year).toSet(), {2019, 2027});
  });

  test('只有需解析的源时，不说自己可播', () {
    final hits = [
      _hit(_site('a', 'A站'), _item('某片', direct: false)),
    ];
    final work = WorkAggregator().group(hits).single;
    expect(work.hasDirectSource, isFalse);
    expect(work.playableNow, isFalse);
    expect(work.headline, contains('需网页解析'));
    expect(work.directSources, isEmpty);
  });

  test('本地已有的集数要计入，并排到前面', () {
    final hits = [
      _hit(_site('a', 'A站'), _item('甄嬛传', year: '2011')),
      _hit(_site('b', 'B站'), _item('另部片', year: '2020')),
    ];
    final works = WorkAggregator().group(
      hits,
      local: [
        _local('甄嬛传', show: '甄嬛传'),
        _local('甄嬛传 第02集', show: '甄嬛传'),
      ],
    );
    final zhenhuan = works.firstWhere((w) => w.title == '甄嬛传');
    expect(zhenhuan.localEpisodes, 2);
    expect(zhenhuan.playableNow, isTrue);
    expect(zhenhuan.headline, contains('本地 2 集'));
    expect(works.first.title, '甄嬛传', reason: '本地有货的排最前');
  });

  test('归一化：去噪声、去季集号，但保留续集数字', () {
    expect(
      WorkAggregator.normalizeTitle('流浪地球2.The.Wandering.Earth.II.2023.1080p.WEB-DL'),
      '流浪地球2thewanderingearthii2023',
    );
    expect(WorkAggregator.normalizeTitle('甄嬛传 第01集'), '甄嬛传');
    expect(
      WorkAggregator.normalizeTitle('流浪地球'),
      isNot(WorkAggregator.normalizeTitle('流浪地球2')),
    );
  });

  test('结果条数有上限，且可播的排在不可播之前', () {
    final hits = [
      for (var i = 0; i < 6; i++)
        _hit(
          _site('a', 'A站'),
          _item('片$i', year: '2020', direct: false),
        ),
      _hit(_site('b', 'B站'), _item('能播的片', year: '2021')),
    ];
    final works = WorkAggregator(maxWorks: 3).group(hits);
    expect(works.length, 3);
    expect(works.first.title, '能播的片');
  });
}
