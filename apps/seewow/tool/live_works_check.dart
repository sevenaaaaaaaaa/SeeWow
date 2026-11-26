// ignore_for_file: avoid_print
// 真网探针：把 20 个采集站的搜索结果按「作品」聚合，看少了几行。
//
//   cd apps/seewow && dart run tool/live_works_check.dart 庆余年
import 'dart:convert';
import 'dart:io';

import 'package:seewow/domain/online_source.dart';
import 'package:seewow/sources/online_vod_service.dart';
import 'package:seewow/metadata/douban_client.dart';
import 'package:seewow/sources/work_aggregator.dart';
import 'package:seewow/sources/work_enricher.dart';

Future<void> main(List<String> args) async {
  final keyword = args.isEmpty ? '庆余年' : args.first;
  final pack = jsonDecode(
    File('assets/sources/builtin_sources.json').readAsStringSync(),
  ) as Map;
  final sites = dedupeSites(
    (pack['sites'] as List)
        .map(OnlineSite.fromJson)
        .whereType<OnlineSite>()
        .where((s) => s.enabled),
  );
  print('站点 ${sites.length} 个 · 关键词「$keyword」');

  final service = OnlineVodService();
  final outcome = await service.search(sites, keyword);
  print('原始命中: ${outcome.hits.length} 行（站点 ${outcome.siteCount} 个）');

  final grouped = WorkAggregator().group(outcome.hits);
  print('聚合后: ${grouped.length} 部作品');

  // 豆瓣补全：只看前 6 部，跟界面默认值一致。
  final enricher = WorkEnricher(source: DoubanClient(), maxWorks: 6);
  final works = await enricher.enrich(
    grouped,
    onProgress: (done, total) => stdout.write('\r  补豆瓣 $done/$total'),
  );
  stdout.write('\r');
  enricher.source.close();
  for (final work in works.take(8)) {
    final score = work.rating == null ? '—' : work.rating!.toStringAsFixed(1);
    print('  · ${work.title}${work.year == null ? '' : ' (${work.year})'} ★$score — ${work.headline}');
    for (final source in work.sources.take(3)) {
      print('      ${source.label}');
    }
  }
  print('失败站点: ${outcome.failures.length} 个 ${outcome.failures.keys.take(5).toList()}');
}
