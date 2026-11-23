import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/metadata_source.dart';
import 'package:seewow/sources/work_aggregator.dart';
import 'package:seewow/sources/work_enricher.dart';

class _FakeDouban extends MetadataSource {
  _FakeDouban({this.catalog = const {}, this.failOn = const {}});

  final Map<String, MediaMetadata> catalog;
  final Set<String> failOn;
  final searched = <String>[];

  @override
  String get id => 'douban';

  @override
  String get label => '豆瓣';

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
    if (failOn.contains(query)) throw const FormatException('接口限流');
    final hit = catalog[query];
    return hit == null ? const [] : [hit];
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async => candidate;
}

MediaMetadata _meta(String title, {int? year, double? rating, String poster = '', String overview = ''}) =>
    MediaMetadata(
      id: title.hashCode,
      mediaType: 'tv',
      title: title,
      overview: overview,
      year: year,
      genres: const [],
      rating: rating,
      posterUrl: poster.isEmpty ? null : poster,
      duration: 0,
      provider: 'douban',
      originalTitle: '',
      originalLanguage: '',
      language: 'zh',
    );

Work _work(String title, {int? year, double? rating, String poster = ''}) => Work(
  id: title,
  title: title,
  year: year,
  posterUrl: poster.isEmpty ? null : poster,
  rating: rating,
  overview: '',
  sources: const [],
  localEpisodes: 0,
);

void main() {
  test('豆瓣评分、海报、简介填进作品行', () async {
    final source = _FakeDouban(
      catalog: {
        '庆余年': _meta(
          '庆余年',
          year: 2019,
          rating: 8.0,
          poster: 'https://img.example/qy.jpg',
          overview: '一个穿越者的故事。',
        ),
      },
    );
    final works = await WorkEnricher(
      source: source,
      gap: Duration.zero,
    ).enrich([_work('庆余年', year: 2019)]);

    expect(works.single.rating, closeTo(8.0, 0.01));
    expect(works.single.posterUrl, contains('qy.jpg'));
    expect(works.single.overview, contains('穿越'));
  });

  test('已有评分的不再发请求', () async {
    final source = _FakeDouban();
    final works = await WorkEnricher(source: source, gap: Duration.zero)
        .enrich([_work('某片', rating: 9.1)]);
    expect(works.single.rating, closeTo(9.1, 0.01));
    expect(source.searched, isEmpty);
  });

  test('一次只补前 N 部，避免把豆瓣打到限流', () async {
    final source = _FakeDouban(
      catalog: {
        for (var i = 0; i < 10; i++) '片$i': _meta('片$i', rating: 7.0),
      },
    );
    final works = await WorkEnricher(
      source: source,
      maxWorks: 3,
      gap: Duration.zero,
    ).enrich([for (var i = 0; i < 10; i++) _work('片$i')]);

    expect(source.searched.length, 3);
    expect(works.where((w) => w.rating != null).length, 3);
  });

  test('片名不完全一致就不认，宁可留空也不写错评分', () async {
    final source = _FakeDouban(
      catalog: {
        '流浪地球2': _meta('流浪地球', year: 2019, rating: 7.9),
      },
    );
    final works = await WorkEnricher(source: source, gap: Duration.zero)
        .enrich([_work('流浪地球2')]);
    expect(works.single.rating, isNull);
  });

  test('年份相差太大不认', () async {
    final source = _FakeDouban(
      catalog: {'某片': _meta('某片', year: 2001, rating: 8.8)},
    );
    final works = await WorkEnricher(source: source, gap: Duration.zero)
        .enrich([_work('某片', year: 2024)]);
    expect(works.single.rating, isNull);
  });

  test('接口失败只影响那一条，其余照常补全', () async {
    final source = _FakeDouban(
      catalog: {'好片': _meta('好片', rating: 8.2)},
      failOn: {'坏片'},
    );
    final works = await WorkEnricher(source: source, gap: Duration.zero)
        .enrich([_work('坏片'), _work('好片')]);
    expect(works[0].rating, isNull);
    expect(works[1].rating, closeTo(8.2, 0.01));
  });

  test('补全不覆盖已有的海报与年份', () async {
    final source = _FakeDouban(
      catalog: {
        '某片': _meta('某片', year: 2020, rating: 7.5, poster: 'https://douban/x.jpg'),
      },
    );
    final works = await WorkEnricher(source: source, gap: Duration.zero)
        .enrich([_work('某片', year: 2020, poster: 'https://cdn/original.jpg')]);
    expect(works.single.posterUrl, contains('cdn/original.jpg'));
  });
}
