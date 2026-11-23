import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/batch_scraper.dart';
import 'package:seewow/metadata/metadata_registry.dart';
import 'package:seewow/metadata/metadata_source.dart';

/// 可控的假数据源：想让哪个片名命中、哪条报错，都在这里写死。
class _FakeSource extends MetadataSource {
  _FakeSource({
    required this.catalog,
    this.failOn = const {},
    this.provider = 'douban',
  });

  /// 片名 → 该源返回的候选。
  final Map<String, List<MediaMetadata>> catalog;

  /// 这些片名一查就抛错，用来验证「一条失败不拖垮整批」。
  final Set<String> failOn;
  final String provider;

  final searched = <String>[];
  int detailCalls = 0;

  @override
  String get id => provider;

  @override
  String get label => '假数据源';

  @override
  bool get seriesOnly => false;

  @override
  void close() {}

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    searched.add(query);
    if (failOn.contains(query)) {
      throw const FormatException('接口挂了');
    }
    return catalog[query] ?? const [];
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    detailCalls++;
    return candidate;
  }
}

MediaMetadata _meta({
  required int id,
  required String title,
  int? year,
  String poster = '',
  String overview = '',
  double? rating,
  bool reviewed = false,
}) => MediaMetadata(
  id: id,
  mediaType: 'movie',
  title: title,
  overview: overview,
  year: year,
  genres: const ['剧情'],
  rating: rating,
  posterUrl: poster.isEmpty ? null : poster,
  duration: 0,
  provider: 'douban',
  originalTitle: '',
  originalLanguage: '',
  language: 'zh',
  reviewed: reviewed,
);

MediaItem _item(
  String id,
  String title, {
  int? year,
  MediaKind kind = MediaKind.movie,
  MediaMetadata? metadata,
}) => MediaItem(
  id: id,
  sourceId: 'src',
  kind: kind,
  title: title,
  locator: '/media/$title.mkv',
  year: year,
  metadata: metadata,
);

void main() {
  test('只补空白：已有封面不动，缺的简介补上', () async {
    final source = _FakeSource(
      catalog: {
        '流浪地球': [
          _meta(
            id: 1,
            title: '流浪地球',
            year: 2019,
            poster: 'https://img.example/poster.jpg',
            overview: '太阳即将毁灭，人类在地球表面建造出巨大的推进器。',
            rating: 7.9,
          ),
        ],
      },
    );
    final registry = MetadataRegistry([source]);
    final applied = <String, MediaMetadata>{};
    final item = _item(
      'a',
      '流浪地球',
      year: 2019,
      metadata: _meta(id: 9, title: '流浪地球', poster: 'https://mine/p.jpg'),
    );

    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([item], apply: (id, match) async => applied[id] = match);

    expect(report.matched, 1);
    final merged = applied['a']!;
    expect(merged.posterUrl, 'https://mine/p.jpg', reason: '已有封面不能被覆盖');
    expect(merged.overview, contains('推进器'));
    expect(merged.rating, closeTo(7.9, 0.01));
    registry.close();
  });

  test('手动确认过的条目一律不动', () async {
    final source = _FakeSource(catalog: {});
    final registry = MetadataRegistry([source]);
    var applied = 0;
    final item = _item(
      'b',
      '甄嬛传',
      metadata: _meta(id: 3, title: '甄嬛传', reviewed: true),
    );

    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([item], apply: (_, _) async => applied++);

    expect(report.skipped, 1);
    expect(report.outcomes.first.detail, contains('已手动确认'));
    expect(applied, 0);
    expect(source.searched, isEmpty, reason: '跳过就不要发请求');
    registry.close();
  });

  test('封面和简介都齐了就不打扰接口', () async {
    final source = _FakeSource(catalog: {});
    final registry = MetadataRegistry([source]);
    final item = _item(
      'c',
      '海贼王',
      metadata: _meta(
        id: 4,
        title: '海贼王',
        poster: 'https://x/p.jpg',
        overview: '已有简介',
      ),
    );
    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([item], apply: (_, _) async {});
    expect(report.skipped, 1);
    expect(source.searched, isEmpty);
    registry.close();
  });

  test('音频不参与刮削', () async {
    final registry = MetadataRegistry([_FakeSource(catalog: {})]);
    final item = _item('d', '某张专辑', kind: MediaKind.audio);
    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([item], apply: (_, _) async {});
    expect(report.skipped, 1);
    expect(report.outcomes.first.detail, contains('音频'));
    registry.close();
  });

  test('年份差超过一年：判失败，不写错海报', () async {
    final source = _FakeSource(
      catalog: {
        '流浪地球': [
          _meta(id: 5, title: '流浪地球', year: 1999, poster: 'https://x/w.jpg'),
        ],
      },
    );
    final registry = MetadataRegistry([source]);
    var applied = 0;
    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([_item('e', '流浪地球', year: 2019)], apply: (_, _) async => applied++);

    expect(report.failed, 1);
    expect(applied, 0);
    expect(report.outcomes.first.detail, contains('没有足够接近'));
    registry.close();
  });

  test('片名像但不是同一部：续集不能被当成正传', () async {
    final source = _FakeSource(
      catalog: {
        '流浪地球2': [
          _meta(id: 6, title: '流浪地球', year: 2019, poster: 'https://x/1.jpg'),
        ],
      },
    );
    final registry = MetadataRegistry([source]);
    var applied = 0;
    // 条目没有年份——这时只认「几乎一模一样」的标题，续集必须落空。
    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([_item('f', '流浪地球2')], apply: (_, _) async => applied++);

    expect(report.failed, 1);
    expect(applied, 0);
    registry.close();
  });

  test('一条接口失败不拖垮整批', () async {
    final source = _FakeSource(
      catalog: {
        '甄嬛传': [
          _meta(id: 7, title: '甄嬛传', year: 2011, poster: 'https://x/z.jpg', overview: '清宫戏'),
        ],
      },
      failOn: {'坏片名'},
    );
    final registry = MetadataRegistry([source]);
    final applied = <String>[];
    final report = await BatchScraper(
      registry: registry,
      gap: Duration.zero,
    ).run([
      _item('g', '坏片名'),
      _item('h', '甄嬛传', year: 2011),
    ], apply: (id, _) async => applied.add(id));

    expect(report.failed, 1);
    expect(report.matched, 1);
    expect(applied, ['h']);
    expect(
      report.outcomes.firstWhere((o) => o.itemId == 'g').detail,
      contains('接口挂了'),
    );
    registry.close();
  });

  test('停止后不再继续发请求', () async {
    final source = _FakeSource(
      catalog: {
        for (var i = 0; i < 6; i++)
          '片$i': [_meta(id: 100 + i, title: '片$i', poster: 'https://x/$i.jpg')],
      },
    );
    final registry = MetadataRegistry([source]);
    var done = 0;
    final report = await BatchScraper(
      registry: registry,
      concurrency: 1,
      gap: Duration.zero,
    ).run(
      [for (var i = 0; i < 6; i++) _item('i$i', '片$i')],
      apply: (_, _) async => done++,
      // 处理完第一个就喊停。
      cancelled: () => done >= 1,
    );

    expect(report.stopped, isTrue);
    expect(report.outcomes.length, lessThan(6));
    expect(source.searched.length, lessThan(6));
    registry.close();
  });

  test('默认不抓简介：整批只发搜索请求', () async {
    final source = _FakeSource(
      catalog: {
        '某片': [_meta(id: 11, title: '某片', poster: 'https://x/p.jpg', rating: 7.0)],
      },
    );
    final registry = MetadataRegistry([source]);
    await BatchScraper(registry: registry, gap: Duration.zero).run(
      [_item('k', '某片')],
      apply: (_, _) async {},
    );
    expect(source.detailCalls, 0, reason: '简介默认不抓，否则请求量翻倍');
    registry.close();
  });

  test('打开 fillOverview 才会去取详情', () async {
    final source = _FakeSource(
      catalog: {
        '某片': [_meta(id: 12, title: '某片', poster: 'https://x/p.jpg', rating: 7.0)],
      },
    );
    final registry = MetadataRegistry([source]);
    await BatchScraper(
      registry: registry,
      gap: Duration.zero,
      fillOverview: true,
    ).run([_item('l', '某片')], apply: (_, _) async {});
    expect(source.detailCalls, 1);
    registry.close();
  });

  test('自动写入的资料不算「人确认过」，下一轮还能再补', () async {
    final source = _FakeSource(
      catalog: {
        '某片': [_meta(id: 8, title: '某片', poster: 'https://x/m.jpg')],
      },
    );
    final registry = MetadataRegistry([source]);
    final applied = <String, MediaMetadata>{};
    await BatchScraper(registry: registry, gap: Duration.zero).run(
      [_item('j', '某片')],
      apply: (id, match) async => applied[id] = match,
    );
    expect(applied['j']!.reviewed, isFalse);
    registry.close();
  });
}
