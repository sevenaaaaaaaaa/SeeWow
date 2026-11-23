import '../domain/media_metadata.dart';
import '../domain/media_review.dart';
import 'metadata_source.dart';
import 'metadata_transport.dart';

/// AniList：动漫的免费 GraphQL 目录，无密钥，封面 / 作品信息 / 评分 / 评论一次拿全。
///
/// 为什么是它：Jikan（MyAnimeList 镜像）、Bangumi、Kitsu 这台机器上都连不上，
/// AniList 是本机实测唯一稳定可用的免疫权动漫源；它同时提供剧集与剧场版，
/// 所以 [seriesOnly] 为 false。
class AniListClient implements MetadataSource {
  AniListClient({Uri? base, MetadataTransport? transport})
    : _base = base ?? Uri.parse('https://graphql.anilist.co'),
      _http =
          transport ?? MetadataTransport(timeout: const Duration(seconds: 20));

  final Uri _base;
  final MetadataTransport _http;

  static const _searchQuery = r'''
query ($q: String, $page: Int) {
  Page(page: $page, perPage: 20) {
    media(search: $q, type: ANIME, sort: SEARCH_MATCH) {
      id
      title { romaji native english }
      coverImage { large extraLarge }
      bannerImage
      description(asHtml: false)
      averageScore
      episodes
      seasonYear
      genres
      format
      status
    }
  }
}''';

  static const _detailsQuery = r'''
query ($id: Int) {
  Media(id: $id) {
    id
    title { romaji native english }
    coverImage { large extraLarge }
    bannerImage
    description(asHtml: false)
    averageScore
    episodes
    duration
    seasonYear
    startDate { year month day }
    genres
    format
    status
    studios(isMain: true) { nodes { name } }
    characters(sort: [ROLE, RELEVANCE], perPage: 12) {
      nodes { name { full } }
    }
  }
}''';

  /// 评论单独一次请求：详情页打开时不一定要拉评论，用户点开才查。
  static const _reviewsQuery = r'''
query ($id: Int, $n: Int) {
  Media(id: $id) {
    reviews(page: 1, perPage: $n) {
      nodes { summary score createdAt user { name } }
    }
  }
}''';

  @override
  String get id => 'anilist';

  @override
  String get label => 'AniList（动漫 · 免密钥）';

  @override
  bool get seriesOnly => false;

  @override
  bool get supportsReviews => true;

  @override
  void close() => _http.close();

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final raw = await _http.json(
      _base,
      headers: const {'Accept': 'application/json'},
      body: {'query': query, 'variables': variables},
      maxBytes: 4 * 1024 * 1024,
    );
    if (raw is! Map) throw const FormatException('AniList 返回的不是 JSON 对象');
    final errors = raw['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? first['message'] : first;
      throw FormatException('AniList 拒绝了这次查询：${message ?? '未知原因'}');
    }
    final data = raw['data'];
    if (data is! Map) throw const FormatException('AniList 没有返回 data');
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (page < 1 || page > 10) {
      throw const FormatException('AniList 只支持前 10 页结果');
    }
    final data = await _post(_searchQuery, {'q': trimmed, 'page': page});
    final pageData = data['Page'];
    final media = pageData is Map ? pageData['media'] : null;
    if (media is! List) return const [];
    final results = <MediaMetadata>[];
    for (final entry in media.whereType<Map>()) {
      final parsed = _parseAnime(Map<String, dynamic>.from(entry));
      if (parsed == null) continue;
      if (year != null && parsed.year != null && parsed.year != year) continue;
      results.add(parsed);
    }
    return results;
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    final data = await _post(_detailsQuery, {'id': candidate.id});
    final media = data['Media'];
    if (media is! Map) throw const FormatException('AniList 没有返回这部动漫');
    final parsed = _parseAnime(
      Map<String, dynamic>.from(media),
      withExtras: true,
    );
    if (parsed == null) throw const FormatException('AniList 动漫详情格式无效');
    return parsed;
  }

  @override
  Future<List<MediaReview>> reviews(
    MediaMetadata candidate, {
    int limit = 10,
  }) async {
    final data = await _post(_reviewsQuery, {
      'id': candidate.id,
      'n': limit.clamp(1, 25),
    });
    final media = data['Media'];
    final reviews = media is Map ? media['reviews'] : null;
    final nodes = reviews is Map ? reviews['nodes'] : null;
    if (nodes is! List) return const [];
    return [
      for (final node in nodes.whereType<Map>())
        if (_review(Map<String, dynamic>.from(node)) case final review?) review,
    ];
  }

  MediaReview? _review(Map<String, dynamic> node) {
    final summary = (node['summary'] as String? ?? '').trim();
    if (summary.isEmpty) return null;
    final user = node['user'];
    final score = (node['score'] as num?)?.toDouble();
    return MediaReview(
      source: 'anilist',
      author: user is Map ? (user['name'] as String? ?? '') : '',
      text: summary,
      // AniList 的评论分是百分制。
      score: score == null || score <= 0 ? null : score / 10,
      maxScore: 10,
      createdAt: switch (node['createdAt']) {
        final int seconds when seconds > 0 =>
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        _ => null,
      },
    );
  }

  MediaMetadata? _parseAnime(
    Map<String, dynamic> media, {
    bool withExtras = false,
  }) {
    final rawId = media['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null) return null;

    final title = media['title'];
    final romaji = title is Map ? (title['romaji'] as String? ?? '') : '';
    final native = title is Map ? (title['native'] as String? ?? '') : '';
    final english = title is Map ? (title['english'] as String? ?? '') : '';
    final display = [native, romaji, english].firstWhere(
      (value) => value.trim().isNotEmpty,
      orElse: () => '',
    );
    if (display.trim().isEmpty) return null;

    final cover = media['coverImage'];
    final poster = cover is Map
        ? (cover['extraLarge'] as String? ?? cover['large'] as String? ?? '')
        : '';
    final banner = media['bannerImage'] as String? ?? '';
    final score = (media['averageScore'] as num?)?.toDouble();

    // AniList 的季番是 TV，剧场版是 MOVIE；两者都属于「动漫」。
    final format = (media['format'] as String? ?? '').toUpperCase();
    final mediaType = format == 'MOVIE' ? 'movie' : 'tv';

    final genres = [
      for (final g in (media['genres'] as List? ?? const []))
        if (g is String && g.isNotEmpty) g,
    ];

    final people = <MediaPerson>[];
    if (withExtras) {
      final characters = media['characters'];
      final nodes = characters is Map ? characters['nodes'] : null;
      if (nodes is List) {
        for (final node in nodes.whereType<Map>()) {
          final name = node['name'];
          final full = name is Map ? (name['full'] as String? ?? '') : '';
          if (full.trim().isNotEmpty) {
            people.add(MediaPerson(name: full, department: 'Characters'));
          }
        }
      }
      final studios = media['studios'];
      final studioNodes = studios is Map ? studios['nodes'] : null;
      if (studioNodes is List) {
        for (final node in studioNodes.whereType<Map>()) {
          final studio = node['name'] as String? ?? '';
          if (studio.trim().isNotEmpty) {
            people.add(MediaPerson(name: studio, role: '动画制作', department: 'Crew'));
          }
        }
      }
    }

    return MediaMetadata(
      id: id,
      mediaType: mediaType,
      title: display,
      overview: plainText(media['description'] as String?),
      year: (media['seasonYear'] as num?)?.toInt(),
      genres: genres,
      rating: score == null ? null : score / 10,
      posterUrl: poster.isEmpty ? null : poster,
      backdropUrl: banner.isEmpty ? null : banner,
      duration: ((media['duration'] as num?) ?? media['episodes'] as num?)
              ?.toDouble() ??
          0,
      provider: id2Provider,
      originalTitle: romaji,
      originalLanguage: 'ja',
      language: 'ja',
      countries: const ['JP'],
      people: people,
      externalIds: {'anilist': '$id'},
    );
  }

  /// 提供商短名，和 `providerLabel` 里的分支对应。
  static const id2Provider = 'anilist';
}
