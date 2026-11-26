// ignore_for_file: avoid_print
// 手动探针：用真实网络跑一遍「免费源」链路，四个场景各查一次。
//
//   cd apps/seewow && flutter pub run tool/live_metadata_check.dart
//
// 不进 CI：它依赖外网。单元测试用 test/fixtures/ 里的真实响应做离线验证，
// 这个脚本只负责回答「今天这几支接口还对得上吗」。
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/batch_scraper.dart';
import 'package:seewow/metadata/anilist_client.dart';
import 'package:seewow/metadata/douban_client.dart';
import 'package:seewow/metadata/metadata_registry.dart';

Future<void> main() async {
  final registry = MetadataRegistry([DoubanClient(), AniListClient()]);

  // ---- 批量刮削：四条真片名 + 一条乱写的，看它会不会乱配 ----
  print('\n=== 批量刮削（5 个条目）===');
  final library = [
    MediaItem(id: 'm1', sourceId: 's', kind: MediaKind.movie, title: '流浪地球', locator: '/x/1.mkv', year: 2019),
    MediaItem(id: 'm2', sourceId: 's', kind: MediaKind.episode, title: '甄嬛传', locator: '/x/2.mkv', year: 2011),
    MediaItem(id: 'm3', sourceId: 's', kind: MediaKind.episode, title: '海贼王', locator: '/x/3.mkv'),
    MediaItem(id: 'm4', sourceId: 's', kind: MediaKind.episode, title: '我在八零年代当后妈', locator: '/x/4.mkv'),
    MediaItem(id: 'm5', sourceId: 's', kind: MediaKind.movie, title: 'zzz不存在的片子zzz', locator: '/x/5.mkv'),
  ];
  final written = <String, MediaMetadata>{};
  final scraper = BatchScraper(registry: registry);
  final report = await scraper.run(
    library,
    apply: (id, match) async => written[id] = match,
    onProgress: (done, total, latest) =>
        print('  [$done/$total] ${latest.title} -> ${latest.detail}'),
  );
  print('  ${report.summary}');
  for (final entry in written.entries) {
    final m = entry.value;
    print('  写入 ${entry.key}: 封面=${m.posterUrl == null ? '无' : '有'} '
        '评分=${m.rating ?? '—'} 简介=${m.overview.isEmpty ? '无' : '${m.overview.length} 字'}');
  }

  for (final probe in const [
    (label: '电影', title: '流浪地球', series: false),
    (label: '剧集', title: '甄嬛传', series: true),
    (label: '动漫', title: '海贼王', series: true),
    (label: '短剧', title: '我在八零年代当后妈', series: true),
  ]) {
    print('\n=== ${probe.label}: ${probe.title} ===');
    try {
      final search = await registry.search(
        probe.title,
        series: probe.series,
        minimum: 1,
      );
      print('  搜索: ${search.summary}');
      final first = search.results.isEmpty ? null : search.results.first;
      if (first == null) {
        print('  ✗ 没有结果');
        continue;
      }
      print(
        '  命中: ${first.title} · ${first.year ?? '—'} · '
        '${first.provider} · 封面 ${first.posterUrl == null ? '无' : '有'}',
      );
      final detail = await registry
          .byId(first.provider)
          ?.details(first);
      if (detail != null) {
        print(
          '  详情: 评分 ${detail.rating ?? '—'} · 类型 ${detail.genres.join('/')} · '
          '地区 ${detail.countries.join('/')}',
        );
      }
      final reviews = await registry.reviews(first, limit: 3);
      print(
        '  评论: ${reviews.isEmpty ? '无（${reviews.error}）' : '${reviews.label} ${reviews.reviews.length} 条'}',
      );
      if (reviews.reviews.isNotEmpty) {
        final r = reviews.reviews.first;
        print('    · ${r.author}｜${r.score ?? '—'}/${r.maxScore}｜${r.text.substring(0, r.text.length.clamp(0, 40))}…');
      }
    } catch (error) {
      print('  ✗ 失败: $error');
    }
  }
  registry.close();
}