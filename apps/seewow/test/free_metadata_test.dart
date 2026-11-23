import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/domain/media_review.dart';
import 'package:seewow/metadata/anilist_client.dart';
import 'package:seewow/metadata/douban_client.dart';
import 'package:seewow/metadata/metadata_registry.dart';
import 'package:seewow/metadata/metadata_source.dart';
import 'package:seewow/metadata/metadata_transport.dart';

/// 固化下来的真实响应（2026-11-23 抓的），不是手写样例：
/// 手写的 JSON 只能证明「我以为接口长这样」，证明不了接口真的长这样。
String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// 只换掉网络这一层，解析路径全走真代码。
class _FixtureTransport extends MetadataTransport {
  _FixtureTransport(this.onRequest);

  final Object? Function(Uri uri, Map<String, dynamic>? body) onRequest;

  @override
  Future<Object?> json(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
    bool allowLan = false,
    int maxBytes = 4 * 1024 * 1024,
  }) async => onRequest(uri, body);
}

void main() {
  group('豆瓣（免密钥）', () {
    test('搜索建议给出片名、年份、封面', () async {
      final client = DoubanClient(
        transport: _FixtureTransport(
          (uri, _) => jsonDecode(_fixture('douban_suggest.json')),
        ),
      );
      final results = await client.search('流浪地球', series: false);
      expect(results, isNotEmpty);
      final first = results.first;
      expect(first.title, '流浪地球');
      expect(first.year, 2019);
      expect(first.provider, 'douban');
      expect(first.posterUrl, isNotNull);
      expect(first.posterUrl, contains('doubanio.com'));
      expect(first.externalIds['douban'], isNotNull);
      client.close();
    });

    test('详情读出评分、类型、地区、导演与演员', () async {
      final client = DoubanClient(
        transport: _FixtureTransport((uri, _) {
          expect(uri.path, contains('subject_abstract'));
          return jsonDecode(_fixture('douban_abstract.json'));
        }),
      );
      const candidate = MediaMetadata(
        id: 26266893,
        mediaType: 'movie',
        title: '流浪地球',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'douban',
        originalTitle: '',
        originalLanguage: '',
        language: 'zh',
      );
      final detail = await client.details(candidate);
      // 「流浪地球‎ (2019)」里的年份和方向标记不能留在片名里。
      expect(detail.title, '流浪地球');
      expect(detail.rating, closeTo(7.9, 0.01));
      expect(detail.year, 2019);
      expect(detail.genres, contains('科幻'));
      expect(detail.countries, isNotEmpty);
      expect(
        detail.people.map((p) => p.name),
        containsAll(['郭帆', '吴京']),
      );
      client.close();
    });

    test('评论给出作者、正文、五星制评分', () async {
      final client = DoubanClient(
        transport: _FixtureTransport((uri, _) {
          expect(uri.path, contains('interests'));
          return jsonDecode(_fixture('douban_interests.json'));
        }),
      );
      const candidate = MediaMetadata(
        id: 26266893,
        mediaType: 'movie',
        title: '流浪地球',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'douban',
        originalTitle: '',
        originalLanguage: '',
        language: 'zh',
      );
      final reviews = await client.reviews(candidate, limit: 6);
      expect(reviews.length, greaterThanOrEqualTo(1));
      final first = reviews.first;
      expect(first.source, 'douban');
      expect(first.author, isNotEmpty);
      expect(first.text.length, greaterThan(20));
      expect(first.maxScore, 5);
      // 没有打分的评论，score 必须是 null，而不是 0。
      for (final review in reviews) {
        if (!review.hasScore) expect(review.score, isNull);
      }
      client.close();
    });
  });

  group('AniList（免密钥）', () {
    test('搜索给出动漫条目、封面与百分制评分归一', () async {
      final client = AniListClient(
        transport: _FixtureTransport(
          (uri, _) => jsonDecode(_fixture('anilist_search.json')),
        ),
      );
      final results = await client.search('海贼王', series: true);
      expect(results, isNotEmpty);
      final first = results.first;
      expect(first.provider, 'anilist');
      expect(first.posterUrl, contains('anilist'));
      expect(first.rating, isNotNull);
      expect(first.rating! <= 10.0, isTrue, reason: '评分要归一到 10 分制');
      expect(first.externalIds['anilist'], isNotNull);
      client.close();
    });

    test('评论给出作者、正文与打分', () async {
      final client = AniListClient(
        transport: _FixtureTransport((uri, body) {
          expect(body?['query'], contains('reviews'));
          return jsonDecode(_fixture('anilist_reviews.json'));
        }),
      );
      const candidate = MediaMetadata(
        id: 21,
        mediaType: 'tv',
        title: 'ONE PIECE',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'anilist',
        originalTitle: '',
        originalLanguage: 'ja',
        language: 'ja',
      );
      final reviews = await client.reviews(candidate, limit: 5);
      expect(reviews, isNotEmpty);
      expect(reviews.first.source, 'anilist');
      expect(reviews.first.author, isNotEmpty);
      expect(reviews.first.createdAt, isNotNull);
      client.close();
    });
  });

  group('注册表：评论按链序回退', () {
    test('豆瓣能答就用豆瓣，答不了换 AniList', () async {
      final registry = MetadataRegistry([
        DoubanClient(
          transport: _FixtureTransport((uri, _) {
            throw const FormatException('豆瓣失败');
          }),
        ),
        AniListClient(
          transport: _FixtureTransport(
            (uri, _) => jsonDecode(_fixture('anilist_reviews.json')),
          ),
        ),
      ]);
      const candidate = MediaMetadata(
        id: 21,
        mediaType: 'tv',
        title: 'ONE PIECE',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'anilist',
        originalTitle: '',
        originalLanguage: 'ja',
        language: 'ja',
      );
      final outcome = await registry.reviews(candidate, limit: 3);
      expect(outcome.sourceId, 'anilist');
      expect(outcome.reviews, isNotEmpty);
      expect(outcome.label, 'AniList');
      registry.close();
    });

    test('没有支持评论的源时说清楚，而不是返回空就算成功', () async {
      final registry = MetadataRegistry(const []);
      const candidate = MediaMetadata(
        id: 1,
        mediaType: 'movie',
        title: 'X',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'douban',
        originalTitle: '',
        originalLanguage: '',
        language: 'zh',
      );
      final outcome = await registry.reviews(candidate);
      expect(outcome.isEmpty, isTrue);
      expect(outcome.error, isNotNull);
      registry.close();
    });
  });


  group('踩过的坑', () {
    test('豆瓣短评先走 /tv/，404 再回落 /movie/', () async {
      final seen = <String>[];
      final client = DoubanClient(
        transport: _FixtureTransport((uri, _) {
          seen.add(uri.path);
          // 真实站点就是这样：电影的 tv 路径 404，剧集的 movie 路径 301。
          if (uri.path.contains('/tv/')) {
            throw const FormatException('服务返回 HTTP 404；请检查接口、授权或额度');
          }
          return jsonDecode(_fixture('douban_interests.json'));
        }),
      );
      const candidate = MediaMetadata(
        id: 26266893,
        mediaType: 'movie',
        title: '流浪地球',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'douban',
        originalTitle: '',
        originalLanguage: '',
        language: 'zh',
      );
      final reviews = await client.reviews(candidate, limit: 3);
      expect(reviews, isNotEmpty);
      expect(seen.first, contains('/v2/tv/26266893/interests'));
      expect(seen.last, contains('/v2/movie/26266893/interests'));
      client.close();
    });

    test('换源前按片名重新搜索，不拿豆瓣 id 去查 AniList', () async {
      final asked = <String>[];
      final fake = _FakeAnime(asked);
      final registry = MetadataRegistry([fake]);
      const candidate = MediaMetadata(
        id: 1453238, // 这是豆瓣的海贼王 id
        mediaType: 'tv',
        title: '海贼王',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'douban',
        originalTitle: '',
        originalLanguage: '',
        language: 'zh',
      );
      final outcome = await registry.reviews(candidate, limit: 2);
      expect(asked, contains('search:海贼王'));
      // 送到 reviews 的必须是本站自己的 id，而不是豆瓣那个。
      expect(asked, contains('reviews:21'));
      expect(outcome.sourceId, 'anilist');
      registry.close();
    });
  });

  test('评论模型：0 分是「没评分」，不是「零分」', () {
    final review = MediaReview.fromJson({
      'source': 'douban',
      'author': '某人',
      'text': '还行',
      'score': null,
      'maxScore': 5,
    });
    expect(review, isNotNull);
    expect(review!.hasScore, isFalse);
    expect(review.normalizedScore, isNull);

    final scored = MediaReview.fromJson({
      'source': 'douban',
      'author': '某人',
      'text': '很好',
      'score': 4,
      'maxScore': 5,
    });
    expect(scored!.hasScore, isTrue);
    expect(scored.normalizedScore, closeTo(8, 0.001));

    expect(MediaReview.fromJson({'text': '   '}), isNull);
  });
}

/// 假动漫源：只为验证「换源要换 id」这条规则。
class _FakeAnime extends MetadataSource {
  _FakeAnime(this.asked);

  final List<String> asked;

  @override
  String get id => 'anilist';

  @override
  String get label => 'AniList（动漫 · 免密钥）';

  @override
  bool get seriesOnly => false;

  @override
  bool get supportsReviews => true;

  @override
  void close() {}

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    asked.add('search:$query');
    return const [
      MediaMetadata(
        id: 21,
        mediaType: 'tv',
        title: 'ONE PIECE',
        overview: '',
        genres: [],
        duration: 0,
        provider: 'anilist',
        originalTitle: '',
        originalLanguage: 'ja',
        language: 'ja',
      ),
    ];
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async => candidate;

  @override
  Future<List<MediaReview>> reviews(
    MediaMetadata candidate, {
    int limit = 10,
  }) async {
    asked.add('reviews:${candidate.id}');
    return const [
      MediaReview(source: 'anilist', author: '人', text: '好看'),
    ];
  }
}
