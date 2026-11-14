import '../domain/media_metadata.dart';
import 'metadata_source.dart';
import 'metadata_transport.dart';

/// Bangumi (bgm.tv): the best open catalogue for Chinese-language anime data.
///
/// The public v0 API needs no token but requires an identifying User-Agent and
/// allows roughly one request per second; both are respected here. This client
/// was written against the documented protocol — the machine this was built on
/// could not reach api.bgm.tv (TCP connect timed out), so it is not yet
/// verified against live responses.
class BangumiClient implements MetadataSource {
  BangumiClient({Uri? base, MetadataTransport? transport})
    : _base = base ?? Uri.parse('https://api.bgm.tv'),
      _http =
          transport ?? MetadataTransport(timeout: const Duration(seconds: 20));

  final Uri _base;
  final MetadataTransport _http;
  DateTime? _lastCall;

  static const _userAgent = 'SeeWow/1.17 (https://github.com/sevenaaaaaaaaa/SeeWow)';

  @override
  String get id => 'bangumi';

  @override
  String get label => 'Bangumi（动画 · 免密钥）';

  @override
  bool get seriesOnly => false;

  @override
  void close() => _http.close();

  Uri _endpoint(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('${_base.toString().replaceAll(RegExp(r'/+$'), '')}$path')
          .replace(queryParameters: query.isEmpty ? null : query);

  /// The API tolerates about one call per second; two concurrent lookups would
  /// otherwise get throttled silently.
  Future<void> _throttle() async {
    final last = _lastCall;
    if (last != null) {
      final waited = DateTime.now().difference(last);
      const minimum = Duration(milliseconds: 1100);
      if (waited < minimum) await Future<void>.delayed(minimum - waited);
    }
    _lastCall = DateTime.now();
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
    await _throttle();
    // type 2 = anime, 1 = book, 3 = music, 4 = game, 6 = real. This app only
    // wants screen media, so anime is the only type requested.
    final json = await _http.json(
      _endpoint('/v0/search/subjects', {'limit': '20', 'offset': '${(page - 1) * 20}'}),
      headers: {'User-Agent': _userAgent, 'Content-Type': 'application/json'},
      body: {
        'keyword': trimmed,
        'filter': {
          'type': [2],
        },
      },
      maxBytes: 4 * 1024 * 1024,
    );
    if (json is! Map) throw const FormatException('Bangumi 没有返回有效的搜索结果');
    final data = json['data'];
    if (data is! List) return const [];
    final results = <MediaMetadata>[];
    for (final entry in data.whereType<Map>()) {
      final parsed = _parse(Map<String, dynamic>.from(entry));
      if (parsed == null) continue;
      if (year != null && parsed.year != null && parsed.year != year) continue;
      results.add(parsed);
    }
    return results;
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    await _throttle();
    final json = await _http.json(
      _endpoint('/v0/subjects/${candidate.id}'),
      headers: {'User-Agent': _userAgent},
      maxBytes: 4 * 1024 * 1024,
    );
    if (json is! Map) throw const FormatException('Bangumi 没有返回条目详情');
    final full = _parse(Map<String, dynamic>.from(json));
    if (full == null) throw const FormatException('Bangumi 条目格式无效');
    final people = await _people(candidate.id);
    return MediaMetadata(
      id: full.id,
      mediaType: full.mediaType,
      title: full.title,
      originalTitle: full.originalTitle,
      overview: full.overview,
      year: full.year,
      genres: full.genres,
      rating: full.rating,
      posterUrl: full.posterUrl,
      backdropUrl: full.backdropUrl,
      duration: full.duration,
      provider: id,
      countries: full.countries,
      people: people,
      externalIds: full.externalIds,
      ratings: full.ratings,
    );
  }

  /// Staff (director, script) is enough: the cast list in Bangumi is long and
  /// only partially relevant to a media library.
  Future<List<MediaPerson>> _people(int subjectId) async {
    try {
      await _throttle();
      final json = await _http.json(
        _endpoint('/v0/subjects/$subjectId/persons'),
        headers: {'User-Agent': _userAgent},
        maxBytes: 4 * 1024 * 1024,
      );
      if (json is! List) return const [];
      final people = <MediaPerson>[];
      for (final entry in json.whereType<Map>()) {
        final name = plainText(entry['name']?.toString());
        if (name.isEmpty) continue;
        final relation = entry['relation']?.toString() ?? '';
        people.add(
          MediaPerson(
            name: name,
            role: relation,
            department: RegExp(r'导演|监督|director', caseSensitive: false)
                    .hasMatch(relation)
                ? 'Directing'
                : 'Cast',
          ),
        );
        if (people.length >= 20) break;
      }
      return people;
    } catch (_) {
      return const [];
    }
  }

  MediaMetadata? _parse(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    final name = plainText(json['name']?.toString());
    final nameCn = plainText(json['name_cn']?.toString());
    final title = nameCn.isNotEmpty ? nameCn : name;
    if (title.isEmpty) return null;
    final images = json['images'];
    final rating = json['rating'];
    final score = rating is Map ? (rating['score'] as num?) : null;
    final ratingTotal = rating is Map ? (rating['total'] as num?) : null;
    final tags = json['tags'];
    final genres = <String>[];
    if (tags is List) {
      for (final tag in tags.whereType<Map>()) {
        final tagName = tag['name']?.toString() ?? '';
        final count = (tag['count'] as num?)?.toInt() ?? 0;
        // Tag names below 3 votes are noise, not a genre.
        if (tagName.isNotEmpty && count >= 3 && genres.length < 8) {
          genres.add(tagName);
        }
      }
    }
    final infobox = json['infobox'];
    String? infoboxValue(String key) {
      if (infobox is! List) return null;
      for (final row in infobox.whereType<Map>()) {
        if (row['key']?.toString() != key) continue;
        final value = row['value'];
        if (value is String) return plainText(value);
        if (value is List) {
          return plainText(
            value
                .whereType<Map>()
                .map((v) => v['v']?.toString() ?? '')
                .where((v) => v.isNotEmpty)
                .join('、'),
          );
        }
      }
      return null;
    }

    final date = (json['date'] ?? infoboxValue('放送开始') ?? '').toString();
    final eps = int.tryParse(infoboxValue('话数') ?? '') ?? 0;
    final durationMinutes = _durationMinutes(infoboxValue('其他') ?? '');
    return MediaMetadata(
      id: id,
      mediaType: 'tv',
      title: title,
      originalTitle: nameCn.isEmpty ? '' : name,
      overview: plainText(json['summary']?.toString()),
      year: yearOf(date),
      genres: genres,
      rating: score == null ? null : score / 2, // Bangumi is 10-point, TMDB 5.
      posterUrl: images is Map ? images['large']?.toString() : null,
      backdropUrl: null,
      duration: durationMinutes * 60,
      provider: 'bangumi',
      language: 'ja',
      countries: const ['日本'],
      ratings: [
        if (score is num)
          MediaRating(
            source: 'Bangumi',
            value: score.toDouble(),
            scale: 10,
            votes: ratingTotal?.toInt(),
          ),
      ],
      externalIds: {
        'bangumi': '$id',
        if (eps > 0) 'bangumi-episodes': '$eps',
      },
    );
  }

  int _durationMinutes(String text) {
    final match = RegExp(r'(\d+)\s*分钟').firstMatch(text);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}
