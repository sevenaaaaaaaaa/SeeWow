import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';

/// 20 个采集站里总有几个要十几秒才回话。搜索是「谁先回谁先显示」，
/// 不是「等最慢的那个」——这条测试钉住前者。
class _Client implements OnlineCmsClient {
  _Client(this.name, this.delay, this.items);

  final String name;
  final Duration delay;
  final List<CmsVodItem> items;

  @override
  Future<List<CmsVodItem>> search(String keyword) async {
    await Future<void>.delayed(delay);
    return items;
  }

  @override
  Future<List<CmsVodItem>> list({int? categoryId, int page = 1}) async => items;

  @override
  Future<List<CmsVodCategory>> categories() async => const [];

  @override
  Future<CmsVodItem?> detail(String id) async => null;

  @override
  void close() {}
}

OnlineSite _site(String id) => OnlineSite(
  id: id,
  name: '$id 站',
  api: 'https://$id.test/api.php/provide/vod',
);

CmsVodItem _item(String name) => CmsVodItem(
  id: name,
  name: name,
  year: '2024',
  remarks: 'HD',
  playFrom: 'lzm3u8',
  playUrl: '正片\$https://cdn.test/$name.m3u8',
);

void main() {
  test('先回话的站点先出结果，后面的回话再补进来', () async {
    final clients = <String, OnlineCmsClient>{
      'https://fast.test/api.php/provide/vod': _Client('fast', Duration.zero, [
        _item('快片'),
      ]),
      'https://slow.test/api.php/provide/vod': _Client(
        'slow',
        const Duration(milliseconds: 120),
        [_item('慢片')],
      ),
    };
    final partials = <OnlineSearchOutcome>[];
    final service = OnlineVodService(
      clientFor: (api) => clients[api]!,
      concurrency: 2,
    );

    final result = await service.search(
      [_site('fast'), _site('slow')],
      '某片',
      onPartial: partials.add,
    );

    expect(partials, hasLength(2), reason: '每回一个站就报一次');
    final first = partials.first;
    expect(first.answered, 1);
    expect(first.hits, hasLength(1));
    expect(first.hits.single.item.name, '快片', reason: '不能等慢站才显示快站的结果');
    expect(partials.last.answered, 2);
    expect(result.hits, hasLength(2));
    // 快照不被后续写入污染：第一份结果永远只有一条。
    expect(first.hits, hasLength(1));
  });

  test('单站超时记进 failures，不拖死整次搜索', () async {
    final clients = <String, OnlineCmsClient>{
      'https://ok.test/api.php/provide/vod': _Client('ok', Duration.zero, [
        _item('有片'),
      ]),
      'https://dead.test/api.php/provide/vod': _Client(
        'dead',
        const Duration(seconds: 2),
        [_item('不会到')],
      ),
    };
    final service = OnlineVodService(
      clientFor: (api) => clients[api]!,
      concurrency: 2,
      perSiteTimeout: const Duration(milliseconds: 60),
    );

    final result = await service.search([_site('ok'), _site('dead')], '某片');

    expect(result.hits, hasLength(1));
    expect(result.failures['dead 站'], '超时未响应');
    expect(result.answered, 2);
  });
}
