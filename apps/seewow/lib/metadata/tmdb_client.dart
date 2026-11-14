import 'dart:convert';

import '../domain/media_metadata.dart';
import '../domain/metadata_languages.dart';
import '../sources/json_api.dart';
import '../sources/native_bridge.dart';
import 'metadata_source.dart';

class MetadataLocale {
  const MetadataLocale({
    this.language = 'zh-CN',
    this.region = '',
    this.fallback = 'en-US',
    this.includeAdult = false,
    this.additionalLanguages = const [],
  });
  final String language, region, fallback;
  final bool includeAdult;
  final List<String> additionalLanguages;
  void validate() {
    final tag = RegExp(r'^[a-z]{2}(?:-[A-Za-z]{2})?$');
    if (!tag.hasMatch(language) ||
        (fallback.isNotEmpty && !tag.hasMatch(fallback)) ||
        (region.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(region)) ||
        additionalLanguages.length > 12 ||
        additionalLanguages.any((code) => !tag.hasMatch(code))) {
      throw const FormatException(
        'TMDB 语言使用 zh-CN / en-US 等代码，地区使用 CN / US 等两位代码',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'language': language,
    'region': region,
    'fallback': fallback,
    'includeAdult': includeAdult,
    'additionalLanguages': additionalLanguages,
  };
  factory MetadataLocale.fromJson(Map<String, dynamic> j) => MetadataLocale(
    language: j['language'] as String? ?? 'zh-CN',
    region: j['region'] as String? ?? '',
    fallback: j['fallback'] as String? ?? 'en-US',
    includeAdult: j['includeAdult'] == true,
    additionalLanguages:
        (j['additionalLanguages'] as List? ?? MetadataLanguage.defaults)
            .cast<String>(),
  );
}

class TmdbClient implements MetadataSource {
  @override
  String get id => 'tmdb';

  @override
  String get label => 'TMDB（电影与剧集）';

  @override
  bool get seriesOnly => false;

  TmdbClient(String token, {Uri? base, this.locale = const MetadataLocale()})
    : _api = JsonApi(
        base ?? Uri.parse('https://api.themoviedb.org/3'),
        headers: {'Authorization': 'Bearer ${token.trim()}'},
        maxBytes: 4 * 1024 * 1024,
      ) {
    if (token.trim().isEmpty)
      throw const FormatException('请先配置 TMDB API Read Access Token');
    locale.validate();
  }
  final JsonApi _api;
  MetadataLocale locale;
  bool hasMore = false;
  final List<String> regionalErrors = [];
  static const tokenKey = 'metadata.tmdb.readToken';
  static const preferencesKey = 'metadata.tmdb.preferences';
  static Future<MetadataLocale> readLocale() async {
    try {
      final raw = await NativeBridge.secretRead(preferencesKey);
      return raw == null
          ? const MetadataLocale(additionalLanguages: MetadataLanguage.defaults)
          : MetadataLocale.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MetadataLocale(
        additionalLanguages: MetadataLanguage.defaults,
      );
    }
  }

  static Future<TmdbClient> configured() async {
    final preferences = await readLocale();
    return TmdbClient(
      await NativeBridge.secretRead(tokenKey) ?? '',
      locale: preferences,
    );
  }

  static Future<void> configure(String token, {MetadataLocale? locale}) async {
    locale?.validate();
    if (token.trim().isEmpty &&
        (await NativeBridge.secretRead(tokenKey) ?? '').isEmpty)
      throw const FormatException('请填写 TMDB API Read Access Token');
    if (token.trim().isNotEmpty)
      await NativeBridge.secretWrite(tokenKey, token.trim());
    if (locale != null)
      await NativeBridge.secretWrite(
        preferencesKey,
        jsonEncode(locale.toJson()),
      );
  }

  static String? imageUrl(Object? path, {bool backdrop = false}) =>
      path is String && RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(path)
      ? 'https://image.tmdb.org/t/p/${backdrop ? 'w1280' : 'w500'}$path'
      : null;

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    bool series = false,
    int? year,
    int page = 1,
  }) async {
    if (query.trim().isEmpty) return [];
    locale.validate();
    if (page < 1 || page > 500) throw const FormatException('搜索页码超出范围');
    final type = series ? 'tv' : 'movie';
    final json = await _api.get('search/$type', {
      'query': query.trim(),
      'language': locale.language,
      'include_adult': '${locale.includeAdult}',
      'page': '$page',
      if (locale.region.isNotEmpty && !series) 'region': locale.region,
      if (year != null) (series ? 'first_air_date_year' : 'year'): '$year',
    });
    final results = json['results'];
    if (results is! List) throw const FormatException('TMDB 没有返回有效的搜索结果');
    hasMore = page < (json['total_pages'] as num? ?? page);
    return results
        .whereType<Map<String, dynamic>>()
        .where((j) => j['id'] is num)
        .take(20)
        .map((j) => _parse(j, type))
        .toList();
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    if (!['movie', 'tv'].contains(candidate.mediaType) || candidate.id <= 0)
      throw const FormatException('此条目不是有效的 TMDB 电影或剧集');
    final j = await _api.get('${candidate.mediaType}/${candidate.id}', {
      'language': locale.language,
      'append_to_response':
          'credits,images,external_ids,translations,alternative_titles',
      'include_image_language': {
        locale.language.split('-').first,
        if (locale.fallback.isNotEmpty) locale.fallback.split('-').first,
        for (final tag in locale.additionalLanguages) tag.split('-').first,
        'null',
      }.join(','),
    });
    if (j['id'] != candidate.id) throw const FormatException('TMDB 详情与所选条目不一致');
    var result = _parse(j, candidate.mediaType);
    if ((result.overview.isEmpty || result.title == '未命名') &&
        locale.fallback.isNotEmpty &&
        locale.fallback != locale.language) {
      final fallback = await _api.get(
        '${candidate.mediaType}/${candidate.id}',
        {'language': locale.fallback},
      );
      if (fallback['id'] != candidate.id)
        throw const FormatException('回退资料与所选条目不一致');
      final other = _parse(fallback, candidate.mediaType);
      result = MediaMetadata.fromJson({
        ...result.toJson(),
        if (result.title == '未命名') 'title': other.title,
        if (result.overview.isEmpty) 'overview': other.overview,
        'notes': ['所选语言资料不完整，缺失文字尝试使用 ${locale.fallback} 回退；人员名称沿用资料源'],
      });
    }
    return result;
  }

  Future<MediaMetadata> episodeDetails(
    MediaMetadata series,
    int season,
    int episode,
  ) async {
    if (series.mediaType != 'tv' || season < 0 || episode < 1)
      throw const FormatException('请先选择剧集，并提供有效季数与集数；特别篇可使用第 0 季');
    final json = await _api.get(
      'tv/${series.id}/season/$season/episode/$episode',
      {
        'language': locale.language,
        'append_to_response': 'credits,images,external_ids,translations',
      },
    );
    if (json['id'] is! num ||
        json['season_number'] != season ||
        json['episode_number'] != episode)
      throw const FormatException('返回的分集与所选季集不一致');
    final result = _parse(json, 'episode');
    return MediaMetadata.fromJson({
      ...result.toJson(),
      'externalIds': {...result.externalIds, 'tmdb_series': '${series.id}'},
    });
  }

  Future<List<MediaMetadata>> searchRegional(
    String query, {
    bool series = false,
    int? year,
    int page = 1,
  }) async {
    final saved = locale;
    final found = <String, MediaMetadata>{};
    var more = false, succeeded = false;
    regionalErrors.clear();
    try {
      for (final code in {saved.language, ...saved.additionalLanguages}) {
        final profile = MetadataLanguage.regional
            .where((p) => p.tag == code)
            .firstOrNull;
        locale = MetadataLocale(
          language: code,
          region: profile?.region ?? saved.region,
          fallback: saved.fallback,
          includeAdult: saved.includeAdult,
        );
        try {
          for (final item in await search(
            query,
            series: series,
            year: year,
            page: page,
          )) {
            found.putIfAbsent('${item.mediaType}:${item.id}', () => item);
          }
          more = more || hasMore;
          succeeded = true;
        } catch (_) {
          regionalErrors.add(code);
        }
      }
      if (!succeeded) throw const FormatException('各语言查询均未成功，请检查服务与凭据');
      return found.values.take(80).toList();
    } finally {
      locale = saved;
      hasMore = more;
    }
  }

  Future<MediaMetadata> collectTranslations(
    MediaMetadata metadata, {
    int? seriesId,
    int? season,
    int? episode,
  }) async {
    String path;
    if (metadata.mediaType == 'episode') {
      if (seriesId == null || season == null || episode == null)
        throw const FormatException('分集缺少剧集 ID 或季集信息，请先确认匹配');
      path = 'tv/$seriesId/season/$season/episode/$episode';
    } else if (['movie', 'tv'].contains(metadata.mediaType) &&
        metadata.id > 0) {
      path = '${metadata.mediaType}/${metadata.id}';
    } else {
      throw const FormatException('需要已确认的电影或剧集 ID');
    }
    final json = await _api.get('$path/translations');
    if (json['id'] != metadata.id || json['translations'] is! List)
      throw const FormatException('译文集合与所选作品不一致');
    final texts = {...metadata.localized};
    for (final entry in _translations(json).entries) {
      texts[entry.key] = (texts[entry.key] ?? const LocalizedMetadata())
          .mergeSource(entry.value);
    }
    return metadata.withLanguages(texts, preferred: locale.additionalLanguages);
  }

  Map<String, LocalizedMetadata> _translations(Map json) {
    final result = <String, LocalizedMetadata>{};
    for (final raw
        in (json['translations'] as List? ?? []).whereType<Map>().take(150)) {
      final language = raw['iso_639_1'];
      final country = raw['iso_3166_1'];
      final data = raw['data'];
      if (language is! String ||
          !RegExp(r'^[a-z]{2}$').hasMatch(language) ||
          data is! Map)
        continue;
      final tag = country is String && RegExp(r'^[A-Z]{2}$').hasMatch(country)
          ? '$language-$country'
          : language;
      final title = (data['title'] ?? data['name'] ?? '').toString().trim();
      final overview = (data['overview'] ?? '').toString().trim();
      if (title.isNotEmpty || overview.isNotEmpty)
        result[tag] = LocalizedMetadata(
          title: title,
          overview: overview,
          provider: 'tmdb',
        );
    }
    return result;
  }

  MediaMetadata _parse(Map<String, dynamic> j, String type) {
    final credits = j['credits'] as Map? ?? {};
    final images = j['images'] as Map? ?? {};
    final people = <MediaPerson>[];
    for (final role in ['cast', 'crew']) {
      for (final raw in (credits[role] as List? ?? []).whereType<Map>().take(
        100,
      )) {
        if (raw['name'] is! String) continue;
        people.add(
          MediaPerson(
            name: raw['name'],
            role: (raw[role == 'cast' ? 'character' : 'job'] ?? '').toString(),
            department: role == 'cast'
                ? 'Cast'
                : (raw['department'] ?? 'Crew').toString(),
            id: raw['id']?.toString(),
            imageUrl: imageUrl(raw['profile_path']),
          ),
        );
      }
    }
    final art = <MediaArtwork>[];
    for (final type in ['posters', 'backdrops']) {
      for (final raw in (images[type] as List? ?? []).whereType<Map>().take(
        60,
      )) {
        final url = imageUrl(raw['file_path'], backdrop: type == 'backdrops');
        if (url != null)
          art.add(
            MediaArtwork(
              url: url,
              type: type == 'posters' ? 'poster' : 'backdrop',
              language: raw['iso_639_1'] as String? ?? '',
              width: raw['width'] as int?,
              height: raw['height'] as int?,
            ),
          );
      }
    }
    final score = (j['vote_average'] as num?)?.toDouble();
    final votes = (j['vote_count'] as num? ?? 0).toInt();
    final rating =
        score != null &&
            votes > 0 &&
            score.isFinite &&
            score >= 0 &&
            score <= 10
        ? score
        : null;
    final original =
        (j[type == 'movie' ? 'original_title' : 'original_name'] ?? '')
            .toString();
    final translated = (j[type == 'movie' ? 'title' : 'name'] ?? '')
        .toString()
        .trim();
    final ids = <String, String>{'tmdb': '${j['id']}'};
    final translatedTexts = j['translations'] is Map
        ? _translations(j['translations'] as Map)
        : <String, LocalizedMetadata>{};
    final alternatives = <String, List<String>>{};
    final rawAlternatives = j['alternative_titles'] as Map? ?? {};
    for (final title
        in (rawAlternatives['titles'] as List? ??
                rawAlternatives['results'] as List? ??
                [])
            .whereType<Map>()
            .take(150)) {
      if (title['iso_3166_1'] is String &&
          title['title'] is String &&
          title['title'].toString().trim().isNotEmpty)
        alternatives
            .putIfAbsent(title['iso_3166_1'], () => [])
            .add(title['title']);
    }
    for (final entry in (j['external_ids'] as Map? ?? {}).entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty)
        ids[entry.key.toString().replaceFirst('_id', '')] = entry.value
            .toString();
    }
    return MediaMetadata(
      id: (j['id'] as num).toInt(),
      adult: j['adult'] as bool?,
      localized: translatedTexts,
      alternativeTitles: alternatives,
      preferredLanguages: locale.additionalLanguages,
      mediaType: type,
      title: translated.isNotEmpty
          ? translated
          : original.isNotEmpty
          ? original
          : '未命名',
      originalTitle: original,
      originalLanguage: j['original_language'] as String? ?? '',
      language: locale.language,
      year: int.tryParse(
        (j[type == 'movie'
                        ? 'release_date'
                        : type == 'tv'
                        ? 'first_air_date'
                        : 'air_date']
                    as String? ??
                '')
            .split('-')
            .first,
      ),
      overview: j['overview'] as String? ?? '',
      genres: (j['genres'] as List? ?? [])
          .whereType<Map>()
          .map((g) => g['name']?.toString() ?? '')
          .where((g) => g.isNotEmpty)
          .toList(),
      rating: rating,
      ratings: [
        if (rating != null)
          MediaRating(source: 'TMDB', value: rating, votes: votes),
      ],
      posterUrl: imageUrl(j['poster_path']),
      backdropUrl: imageUrl(
        j['backdrop_path'] ?? j['still_path'],
        backdrop: true,
      ),
      duration: type != 'tv' ? (j['runtime'] as num? ?? 0).toDouble() * 60 : 0,
      countries: (j['production_countries'] as List? ?? [])
          .whereType<Map>()
          .map((c) => (c['iso_3166_1'] ?? c['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      people: people,
      artworks: art,
      externalIds: ids,
    );
  }

  @override
  void close() => _api.close();
}
