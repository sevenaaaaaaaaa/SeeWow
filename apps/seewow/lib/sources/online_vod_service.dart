import 'dart:async';

import '../domain/online_source.dart';
import 'cms_vod_client.dart';

/// 采集站的最小接口，方便测试时替换成假客户端。
abstract class OnlineCmsClient {
  Future<List<CmsVodItem>> search(String keyword);
  Future<List<CmsVodItem>> list({int? categoryId, int page});
  Future<List<CmsVodCategory>> categories();
  Future<CmsVodItem?> detail(String id);
  void close();
}

/// 真实实现：苹果CMS 采集站。
class HttpOnlineCmsClient implements OnlineCmsClient {
  HttpOnlineCmsClient(String api) : _inner = CmsVodClient(api);
  final CmsVodClient _inner;

  @override
  Future<List<CmsVodItem>> search(String keyword) => _inner.search(keyword);

  @override
  Future<List<CmsVodItem>> list({int? categoryId, int page = 1}) =>
      _inner.list(categoryId: categoryId, page: page);

  @override
  Future<List<CmsVodCategory>> categories() => _inner.categories();

  @override
  Future<CmsVodItem?> detail(String id) => _inner.detail(id);

  @override
  void close() => _inner.close();
}

class OnlineSearchHit {
  const OnlineSearchHit(this.site, this.item, {this.category = ''});
  final OnlineSite site;
  final CmsVodItem item;

  /// 命中的分类名（浏览短剧时是站点的「短剧」分类），搜索时为空。
  final String category;
}

class OnlineSearchOutcome {
  const OnlineSearchOutcome({
    required this.hits,
    required this.failures,
    required this.skipped,
  });

  final List<OnlineSearchHit> hits;

  /// 站点名 → 失败原因，界面直接显示，不藏。
  final Map<String, String> failures;

  /// 返回了结果但没有可播地址的条目数。
  final int skipped;

  bool get isEmpty => hits.isEmpty;
  int get siteCount => hits.map((hit) => hit.site.id).toSet().length;
}

class OnlineVodService {
  OnlineVodService({
    OnlineCmsClient Function(String api)? clientFor,
    this.concurrency = 6,
    this.perSiteTimeout = const Duration(seconds: 18),
  }) : _clientFor = clientFor ?? HttpOnlineCmsClient.new;

  final OnlineCmsClient Function(String api) _clientFor;
  final int concurrency;
  final Duration perSiteTimeout;

  /// 按分类关键词横向浏览（默认「短剧」）。
  ///
  /// 先读每个站的分类表，只拉命中关键词的那几个分类的第一页 —— 采集站的分类
  /// 动辄几十个，全拉一遍既慢又没必要。
  Future<OnlineSearchOutcome> browse(
    List<OnlineSite> sites, {
    String categoryKeyword = '短剧',
    int maxCategoriesPerSite = 2,
    int page = 1,
  }) async {
    if (sites.isEmpty) {
      return const OnlineSearchOutcome(hits: [], failures: {}, skipped: 0);
    }
    final keyword = categoryKeyword.trim();
    final hits = <OnlineSearchHit>[];
    final failures = <String, String>{};
    var skipped = 0;
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= sites.length) return;
        final site = sites[index];
        final client = _clientFor(site.api);
        try {
          final categories = await client.categories().timeout(perSiteTimeout);
          final matched = categories
              .where(
                (category) =>
                    keyword.isEmpty || category.name.contains(keyword),
              )
              .take(maxCategoriesPerSite)
              .toList();
          if (matched.isEmpty) {
            failures[site.name] = '没有「$keyword」分类';
            continue;
          }
          for (final category in matched) {
            final items = await client
                .list(categoryId: category.id, page: page)
                .timeout(perSiteTimeout);
            for (final item in items) {
              if (item.hasPlayableSource) {
                hits.add(OnlineSearchHit(site, item, category: category.name));
              } else {
                skipped++;
              }
            }
          }
        } on TimeoutException {
          failures[site.name] = '超时未响应';
        } on FormatException catch (error) {
          failures[site.name] = error.message;
        } catch (_) {
          failures[site.name] = '无法连接';
        } finally {
          client.close();
        }
      }
    }

    await Future.wait(
      List.generate(concurrency.clamp(1, sites.length), (_) => worker()),
    );
    return OnlineSearchOutcome(
      hits: hits,
      failures: failures,
      skipped: skipped,
    );
  }

  /// 并发搜多个站点；单站失败只记进 failures，不影响其它站的结果。
  Future<OnlineSearchOutcome> search(
    List<OnlineSite> sites,
    String keyword,
  ) async {
    final word = keyword.trim();
    if (word.isEmpty || sites.isEmpty) {
      return const OnlineSearchOutcome(hits: [], failures: {}, skipped: 0);
    }
    final hits = <OnlineSearchHit>[];
    final failures = <String, String>{};
    var skipped = 0;
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= sites.length) return;
        final site = sites[index];
        final client = _clientFor(site.api);
        try {
          final items = await client.search(word).timeout(perSiteTimeout);
          for (final item in items) {
            if (item.hasPlayableSource) {
              hits.add(OnlineSearchHit(site, item));
            } else {
              skipped++;
            }
          }
        } on TimeoutException {
          failures[site.name] = '超时未响应';
        } on FormatException catch (error) {
          failures[site.name] = error.message;
        } catch (_) {
          failures[site.name] = '无法连接';
        } finally {
          client.close();
        }
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, sites.length),
      (_) => worker(),
    );
    await Future.wait(workers);
    hits.sort((a, b) => a.item.name.compareTo(b.item.name));
    return OnlineSearchOutcome(
      hits: hits,
      failures: failures,
      skipped: skipped,
    );
  }
}
