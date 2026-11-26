import '../domain/media_metadata.dart';
import '../domain/media_review.dart';
import 'metadata_source.dart';
import 'metadata_transport.dart';

/// 豆瓣：中文影视覆盖面最广的免费目录，无密钥。
///
/// 用的是豆瓣网页端自己在用的三支 JSON 接口（`/j/subject_suggest`、
/// `/j/subject_abstract`、`m.douban.com` 的 `rexxar/api/v2/.../interests`）。
/// 它们不是官方开放 API，是页面自己调的内部接口：本机实测三支都 200，
/// 评论接口只缺一个 Referer 就会 400，所以请求里固定带上。
///
/// 覆盖：电影、剧集、动漫、短剧——豆瓣把它们都收在同一个 subject 体系里，
/// 短剧无非就是集数很短、`is_tv` 为真的剧集，不需要另一套接口。
class DoubanClient implements MetadataSource {
  DoubanClient({
    Uri? suggestBase,
    Uri? searchBase,
    Uri? abstractBase,
    Uri? interestsBase,
    MetadataTransport? transport,
  }) : _suggest = suggestBase ?? Uri.parse('https://movie.douban.com/j/subject_suggest'),
       _search = searchBase ?? Uri.parse('https://m.douban.com/rexxar/api/v2/search'),
       _abstract =
           abstractBase ?? Uri.parse('https://movie.douban.com/j/subject_abstract'),
       _interests =
           interestsBase ??
           // 只到 /v2 为止：movie / tv 这一段按条目类型再拼，
           // 拼成 /v2/movie/tv/{id} 会 404——当场踩过。
           Uri.parse('https://m.douban.com/rexxar/api/v2'),
       _http = transport ?? MetadataTransport(timeout: const Duration(seconds: 20));

  final Uri _suggest, _search, _abstract, _interests;
  final MetadataTransport _http;

  @override
  String get id => 'douban';

  @override
  String get label => '豆瓣（影视/动漫/短剧 · 免密钥）';

  @override
  bool get seriesOnly => false;

  @override
  bool get supportsReviews => true;

  @override
  void close() => _http.close();

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // 一页就够：这两个接口都不做真正的分页。
    if (page > 1) return const [];
    // 首选 rexxar/v2/search：一次请求就给齐 id、片名、年份、评分、封面、
    // 地区/类型/主创，而且实测抗突发；subject_suggest 每多打几次就会静默
    // 返回空数组（2 字节），只当兜底。
    try {
      final raw = await _http.json(
        _search.replace(queryParameters: {
          'q': trimmed,
          if (series) 'type': 'tv' else 'type': 'movie',
        }),
        headers: const {'Referer': 'https://m.douban.com/'},
        maxBytes: 4 * 1024 * 1024,
      );
      final hits = _parseSearch(raw);
      if (hits.isNotEmpty) {
        return [
          for (final hit in hits)
            if (year == null || hit.year == null || hit.year == year) hit,
        ];
      }
    } catch (_) {
      // 落到下面的 suggest。
    }
    final raw = await _http.json(
      _suggest.replace(queryParameters: {'q': trimmed}),
      maxBytes: 2 * 1024 * 1024,
    );
    if (raw is! List) throw const FormatException('豆瓣没有返回有效的搜索结果');
    final results = <MediaMetadata>[];
    for (final entry in raw.whereType<Map>()) {
      final parsed = _parseSuggestion(Map<String, dynamic>.from(entry));
      if (parsed == null) continue;
      if (year != null && parsed.year != null && parsed.year != year) continue;
      results.add(parsed);
    }
    return results;
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    final raw = await _http.json(
      _abstract.replace(queryParameters: {'subject_id': '${candidate.id}'}),
      maxBytes: 2 * 1024 * 1024,
    );
    if (raw is! Map) throw const FormatException('豆瓣没有返回条目详情');
    final code = raw['r'];
    if (code is num && code != 0) {
      throw const FormatException('豆瓣拒绝了这个条目（可能已下架或需要登录）');
    }
    final subject = raw['subject'];
    if (subject is! Map) throw const FormatException('豆瓣条目详情格式无效');
    return _parseDetail(
      Map<String, dynamic>.from(subject),
      fallback: candidate,
    );
  }

  @override
  Future<List<MediaReview>> reviews(
    MediaMetadata candidate, {
    int limit = 10,
  }) async {
    final count = limit.clamp(1, 40);
    // 电影的短评在 /movie/{id}/interests，剧集和短剧在 /tv/{id}/interests；
    // 走错那条会 301，拿不到评论。两类都是私有路径，所以先试 tv 再回落 movie
    // ——实测剧集与短剧都在 tv 下，电影在 movie 下。
    const kinds = ['tv', 'movie'];
    Object? raw;
    Object? lastError;
    for (final kind in kinds) {
      final uri = _interests.replace(
        pathSegments: [..._interests.pathSegments, kind, '${candidate.id}', 'interests'],
        queryParameters: {'count': '$count', 'start': '0'},
      );
      try {
        raw = await _http.json(
          uri,
          headers: {
            // 不带 Referer 会 400：豆瓣要求请求看起来来自条目页。
            'Referer': 'https://m.douban.com/$kind/subject/${candidate.id}/',
          },
          maxBytes: 2 * 1024 * 1024,
        );
        break;
      } catch (error) {
        lastError = error;
        raw = null;
      }
    }
    if (raw == null) {
      throw lastError is FormatException
          ? lastError
          : const FormatException('豆瓣评论接口不可用');
    }
    if (raw is! Map) throw const FormatException('豆瓣没有返回评论列表');
    final interests = raw['interests'];
    if (interests is! List) return const [];
    return [
      for (final entry in interests.whereType<Map>())
        ?_review(Map<String, dynamic>.from(entry)),
    ];
  }



  /// rexxar/v2/search 的一条结果 → MediaMetadata。
  ///
  /// 这个接口的字段比 suggest 全：`card_subtitle` 用「 / 」把地区、类型、
  /// 导演、主演串成一行，拆开就是国家、类型与主创，不用再发第二支请求。
  List<MediaMetadata> _parseSearch(Object? raw) {
    if (raw is! Map) return const [];
    final subjects = raw['subjects'];
    final items = subjects is Map ? subjects['items'] : null;
    if (items is! List) return const [];
    final results = <MediaMetadata>[];
    for (final entry in items.whereType<Map>()) {
      final target = entry['target'];
      if (target is! Map) continue;
      final data = Map<String, dynamic>.from(target);
      final rawId = data['id'];
      final id = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
      final title = (data['title'] as String? ?? '').trim();
      if (id == null || title.isEmpty) continue;
      final rating = data['rating'];
      final value = rating is Map ? (rating['value'] as num?)?.toDouble() : null;
      final cover = (data['cover_url'] as String? ?? '').trim();
      final targetType = '${entry['target_type'] ?? ''}'.toLowerCase();
      final parsedCard = _cardSubtitle(data['card_subtitle'] as String?);
      results.add(
        MediaMetadata(
          id: id,
          mediaType: targetType == 'tv' ? 'tv' : 'movie',
          title: title,
          overview: '',
          year: _int(data['year']),
          genres: parsedCard.genres,
          rating: value != null && value > 0 ? value : null,
          posterUrl: cover.isEmpty ? null : cover,
          duration: 0,
          provider: 'douban',
          originalTitle: '',
          originalLanguage: '',
          language: 'zh',
          countries: parsedCard.countries,
          people: parsedCard.people,
          externalIds: {'douban': '$id'},
        ),
      );
    }
    return results;
  }

  /// `中国大陆 / 科幻 冒险 灾难 / 郭帆 / 吴京 屈楚萧` → 地区、类型、主创。
  static ({List<String> countries, List<String> genres, List<MediaPerson> people})
  _cardSubtitle(String? text) {
    final empty = (
      countries: const <String>[],
      genres: const <String>[],
      people: const <MediaPerson>[],
    );
    if (text == null || text.trim().isEmpty) return empty;
    final parts = text
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return empty;
    List<String> words(String value) => [
      for (final word in value.split(RegExp(r'\s+')))
        if (word.trim().isNotEmpty) word.trim(),
    ];
    final countries = parts.isNotEmpty ? words(parts[0]) : const <String>[];
    final genres = parts.length > 1 ? words(parts[1]) : const <String>[];
    final people = <MediaPerson>[];
    if (parts.length > 2) {
      for (final name in words(parts[2])) {
        people.add(MediaPerson(name: name, role: '导演', department: 'Crew'));
      }
    }
    if (parts.length > 3) {
      for (final name in words(parts[3])) {
        people.add(MediaPerson(name: name, department: 'Cast'));
      }
    }
    return (countries: countries, genres: genres, people: people);
  }

  /// 豆瓣同一个字段今天返回数组、明天返回一段字符串，两种都得吃得下——
  /// `region` 实测是「中国大陆」，`types` 实测是数组。
  static List<String> _strings(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    }
    if (value is String && value.trim().isNotEmpty) {
      return [
        for (final part in value.split(RegExp(r'\s*/\s*|\s+,')))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    return const [];
  }

  /// 「125分钟」→ 125；「2小时10分」→ 130。读不出来就 0，不猜。
  static double _minutes(Object? value) {
    if (value is num) return value.toDouble();
    if (value is! String) return 0;
    final hours = RegExp(r'(\d+)\s*小时').firstMatch(value);
    final minutes = RegExp(r'(\d+)\s*分').firstMatch(value);
    if (hours == null && minutes == null) return 0;
    final h = int.tryParse(hours?.group(1) ?? '') ?? 0;
    final m = int.tryParse(minutes?.group(1) ?? '') ?? 0;
    return (h * 60 + m).toDouble();
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  MediaReview? _review(Map<String, dynamic> entry) {
    final text = (entry['comment'] as String? ?? '').trim();
    if (text.isEmpty) return null;
    final rating = entry['rating'];
    final value = rating is Map ? (rating['value'] as num?)?.toDouble() : null;
    final max = rating is Map ? (rating['max'] as num?)?.toDouble() : null;
    final user = entry['user'];
    return MediaReview(
      source: 'douban',
      author: user is Map ? (user['name'] as String? ?? '') : '',
      text: text,
      // 0 分在豆瓣表示「没有评分」，不是「零分」。
      score: value == null || value <= 0 ? null : value,
      maxScore: max == null || max <= 0 ? 5 : max,
      createdAt: _parseTime(entry['create_time']),
      votes: (entry['vote_count'] as num?)?.toInt(),
      url: entry['sharing_url'] as String?,
    );
  }

  DateTime? _parseTime(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  MediaMetadata? _parseSuggestion(Map<String, dynamic> entry) {
    final rawId = entry['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    final title = (entry['title'] as String? ?? '').trim();
    if (id == null || title.isEmpty) return null;
    final sub = (entry['sub_title'] as String? ?? '').trim();
    final episode = (entry['episode'] as String? ?? '').trim();
    final year = int.tryParse((entry['year'] as String? ?? '').trim());
    final poster = (entry['img'] as String? ?? '').trim();
    // suggest 里的 type 只在部分条目上可靠；有集数就是剧集，短剧同理。
    final isSeries =
        episode.isNotEmpty && episode.toLowerCase() != 'unknow';
    return MediaMetadata(
      id: id,
      mediaType: isSeries ? 'tv' : 'movie',
      title: title,
      overview: '',
      year: year != null && year > 1800 ? year : null,
      genres: const [],
      posterUrl: poster.isEmpty ? null : poster,
      provider: 'douban',
      originalTitle: sub.isEmpty || sub == title ? '' : sub,
      language: 'zh',
      externalIds: {'douban': '$id'},
      notes: const ['条目取自豆瓣搜索建议，详情需再查一次'],
    );
  }

  MediaMetadata _parseDetail(
    Map<String, dynamic> subject, {
    required MediaMetadata fallback,
  }) {
    final rawTitle = (subject['title'] as String? ?? '').trim();
    // 「流浪地球‎ (2019)」——年份和方向标记要去掉，标题只留片名。
    final title = rawTitle
        .replaceAll('\u200e', '')
        .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
        .trim();
    final rateText = (subject['rate'] as String? ?? '').trim();
    final rate = double.tryParse(rateText);
    final star = (subject['star'] as num?)?.toDouble();
    final types = _strings(subject['types']);
    final regions = _strings(subject['region']);
    final people = <MediaPerson>[
      for (final value in (subject['directors'] as List? ?? const []))
        if (value is String && value.isNotEmpty)
          MediaPerson(name: value, role: '导演', department: 'Crew'),
      for (final value in (subject['actors'] as List? ?? const []))
        if (value is String && value.isNotEmpty)
          MediaPerson(name: value, department: 'Cast'),
    ];
    final isTv = subject['is_tv'] == true;
    final episodes = _int(subject['episodes_count']) ?? 0;

    return MediaMetadata(
      id: fallback.id,
      // 短剧在豆瓣也是剧集：`is_tv` 为真，或集数字段有值。
      mediaType: isTv || episodes > 0 ? 'tv' : fallback.mediaType,
      title: title.isEmpty ? fallback.title : title,
      overview: fallback.overview,
      year: _int(subject['release_year']) ?? fallback.year,
      genres: types.isEmpty ? fallback.genres : types,
      // 豆瓣的 star 是 5 分制；rate 是 10 分制，优先用 rate。
      rating: rate != null && rate > 0
          ? rate
          : (star != null && star > 0 ? star * 2 : fallback.rating),
      posterUrl: fallback.posterUrl,
      backdropUrl: fallback.backdropUrl,
      duration: _minutes(subject['duration']) > 0
          ? _minutes(subject['duration'])
          : fallback.duration,
      provider: 'douban',
      originalTitle: fallback.originalTitle,
      originalLanguage: fallback.originalLanguage,
      language: 'zh',
      countries: regions.isEmpty ? fallback.countries : regions,
      people: people.isEmpty ? fallback.people : people,
      externalIds: {'douban': '${fallback.id}'},
    );
  }
}
