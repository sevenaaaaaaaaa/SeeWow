import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';

class _FakeClient implements OnlineCmsClient {
  _FakeClient(
    this.items, {
    this.failure,
    this.categoryList = const [],
    List<CmsVodItem>? listed,
  }) : listed = listed ?? items;

  final List<CmsVodItem> items;
  final List<CmsVodItem> listed;
  final List<CmsVodCategory> categoryList;
  final Object? failure;
  bool closed = false;
  final List<int?> listedCategories = [];

  @override
  Future<List<CmsVodItem>> search(String keyword) async {
    if (failure != null) throw failure!;
    return items;
  }

  @override
  Future<List<CmsVodItem>> list({int? categoryId, int page = 1}) async {
    if (failure != null) throw failure!;
    listedCategories.add(categoryId);
    return listed;
  }

  @override
  Future<List<CmsVodCategory>> categories() async {
    if (failure != null) throw failure!;
    return categoryList;
  }

  @override
  Future<CmsVodItem?> detail(String id) async => items.firstOrNull;

  @override
  void close() => closed = true;
}

CmsVodItem _item(String name, {String url = 'https://x/1.m3u8'}) => CmsVodItem(
  id: name,
  name: name,
  playFrom: 'lzm3u8',
  playUrl: '第01集' + r'$' + url,
);

void main() {
  group('站点清单', () {
    test('种子去重后没有重复接口', () {
      final unique = dedupeSites(seedOnlineSites);
      // 数量跟着种子走：换源包时改一处，测试不会变成绊脚石。
      expect(seedOnlineSites.length, greaterThanOrEqualTo(12));
      expect(unique.length, seedOnlineSites.length);
      expect(
        unique.map((site) => site.hostKey).toSet().length,
        unique.length,
      );
    });

    test('去重按 host + path，不看查询串写法', () {
      final sites = dedupeSites(const [
        OnlineSite(id: 'a', name: 'A', api: 'https://x.test/api.php/provide/vod'),
        OnlineSite(
          id: 'b',
          name: 'B',
          api: 'https://x.test/api.php/provide/vod/?ac=list',
        ),
        OnlineSite(id: 'c', name: 'C', api: 'https://y.test/api.php/provide/vod'),
      ]);
      expect(sites.map((site) => site.id), ['a', 'c']);
    });
  });

  group('站点存储', () {
    late Directory dir;
    late OnlineSourceStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('seewow-online-');
      store = OnlineSourceStore(directory: dir);
      await store.load();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('首次加载灌入种子并落盘', () async {
      expect(store.sites.length, seedOnlineSites.length);
      final file = File('${dir.path}/online_sources.json');
      expect(await file.exists(), isTrue);
    });

    test('添加自定义站点后拒绝重复地址', () async {
      expect(await store.addSite('测试站', 'https://a.test/api.php/provide/vod'), isTrue);
      expect(await store.addSite('重复', 'https://a.test/api.php/provide/vod/?ac=list'), isFalse);
      expect(store.toast, contains('已经在清单'));
    });

    test('非 http 或带账号的地址拒绝', () async {
      expect(await store.addSite('坏', 'ftp://a.test/x'), isFalse);
      expect(await store.addSite('坏', 'https://u:p@a.test/x'), isFalse);
    });

    test('开关与删除会持久化', () async {
      final first = store.sites.first;
      await store.toggle(first, false);
      expect(store.enabledSites.any((site) => site.id == first.id), isFalse);
      final reloaded = OnlineSourceStore(directory: dir);
      await reloaded.load();
      expect(reloaded.sites.first.enabled, isFalse);
      final before = store.sites.length;
      await store.removeSite(reloaded.sites.first);
      expect(store.sites.length, before - 1);
    });

    test('一键全停 / 全启，只写一次', () async {
      final off = await store.setAll(false);
      expect(off, store.sites.length);
      expect(store.enabledSites, isEmpty);
      final on = await store.setAll(true);
      expect(on, store.sites.length);
      expect(store.enabledSites.length, store.sites.length);
    });

    test('从配置导入只加新接口', () async {
      final added = await store.importFromConfig([
        const OnlineSite(id: 'x', name: '新站', api: 'https://new.test/api.php/provide/vod'),
        // 已经在内置清单里的接口（最大资源）：只该被跳过，不该重复加。
        const OnlineSite(id: 'y', name: '旧站', api: 'https://api.zuidapi.com/api.php/provide/vod/'),
      ]);
      expect(added, 1);
      expect(store.sites.any((site) => site.name == '新站'), isTrue);
    });
  });

  group('聚合搜索', () {
    test('多站点并发，单站失败只记失败原因', () async {
      final service = OnlineVodService(
        clientFor: (api) => api.contains('bad')
            ? _FakeClient(const [], failure: const FormatException('返回格式不对'))
            : _FakeClient([_item('片A'), _item('片B')]),
      );
      const sites = [
        OnlineSite(id: '1', name: '好站', api: 'https://good.test/api.php/provide/vod'),
        OnlineSite(id: '2', name: '坏站', api: 'https://bad.test/api.php/provide/vod'),
      ];
      final outcome = await service.search(sites, '片');
      expect(outcome.hits.length, 2);
      expect(outcome.failures['坏站'], '返回格式不对');
      expect(outcome.siteCount, 1);
    });

    test('没有可播地址的结果计入 skipped', () async {
      final service = OnlineVodService(
        clientFor: (_) => _FakeClient([
          CmsVodItem(id: 'x', name: '无地址', playFrom: 'lzm3u8', playUrl: ''),
        ]),
      );
      final outcome = await service.search(
        const [OnlineSite(id: '1', name: 'S', api: 'https://a.test/api.php')],
        '问',
      );
      expect(outcome.hits, isEmpty);
      expect(outcome.skipped, 1);
    });

    test('空关键词不发请求', () async {
      var calls = 0;
      final service = OnlineVodService(
        clientFor: (_) {
          calls++;
          return _FakeClient([_item('x')]);
        },
      );
      final outcome = await service.search(
        const [OnlineSite(id: '1', name: 'S', api: 'https://a.test/api.php')],
        '   ',
      );
      expect(outcome.hits, isEmpty);
      expect(calls, 0);
    });

    test('按分类浏览：只拉命中的短剧分类，并带上分类名', () async {
      final fake = _FakeClient(
        const [],
        categoryList: const [
          CmsVodCategory(1, '电影'),
          CmsVodCategory(36, '短剧'),
          CmsVodCategory(53, '擦边短剧'),
          CmsVodCategory(54, 'ai短剧'),
        ],
        listed: [_item('短剧甲')],
      );
      final service = OnlineVodService(clientFor: (_) => fake);
      final outcome = await service.browse(
        const [OnlineSite(id: '1', name: 'S', api: 'https://a.test/api.php')],
      );
      expect(outcome.hits.length, 2);
      expect(outcome.hits.first.category, '短剧');
      expect(outcome.hits.first.item.name, '短剧甲');
      // maxCategoriesPerSite 默认 2：短剧 + 擦边短剧，第三个不再请求
      expect(fake.listedCategories, [36, 53]);
    });

    test('站点没有短剧分类时说清楚，而不是静默空', () async {
      final service = OnlineVodService(
        clientFor: (_) => _FakeClient(
          const [],
          categoryList: const [CmsVodCategory(1, '电影')],
        ),
      );
      final outcome = await service.browse(
        const [OnlineSite(id: '1', name: 'S', api: 'https://a.test/api.php')],
      );
      expect(outcome.hits, isEmpty);
      expect(outcome.failures['S'], contains('没有「短剧」分类'));
    });

    test('结果按片名排序，方便扫读', () async {
      final service = OnlineVodService(
        clientFor: (api) => _FakeClient([
          _item(api.contains('b') ? '乙片' : '甲片'),
        ]),
      );
      final outcome = await service.search(
        const [
          OnlineSite(id: '1', name: 'A', api: 'https://a.test/api.php'),
          OnlineSite(id: '2', name: 'B', api: 'https://b.test/api.php'),
        ],
        '片',
      );
      expect(outcome.hits.map((hit) => hit.item.name).toList(), ['乙片', '甲片']);
    });
  });
}
