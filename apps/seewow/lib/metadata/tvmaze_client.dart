import '../domain/media_metadata.dart';
import 'metadata_source.dart';
import 'metadata_transport.dart';

/// TVmaze: free, no API key, and the most reliable open catalogue for series.
/// Films are not covered, which is why [seriesOnly] is true.
class TvMazeClient implements MetadataSource {
  TvMazeClient({Uri? base, MetadataTransport? transport})
    : _base = base ?? Uri.parse('https://api.tvmaze.com'),
      _http =
          transport ?? MetadataTransport(timeout: const Duration(seconds: 20));

  final Uri _base;
  final MetadataTransport _http;

  @override
  String get id => 'tvmaze';

  @override
  String get label => 'TVmaze（剧集 · 免密钥）';

  @override
  bool get seriesOnly => true;

  @override
  void close() => _http.close();

  Uri _endpoint(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('${_base.toString().replaceAll(RegExp(r'/+$'), '')}$path')
          .replace(queryParameters: query.isEmpty ? null : query);

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
      throw const FormatException('TVmaze 只支持前 10 页结果');
    }
    final json = await _http.json(
      _endpoint('/search/shows', {'q': trimmed}),
      maxBytes: 4 * 1024 * 1024,
    );
    if (json is! List) throw const FormatException('TVmaze 没有返回有效的搜索结果');
    final results = <MediaMetadata>[];
    for (final entry in json.whereType<Map>()) {
      final show = entry['show'];
      if (show is! Map) continue;
      final parsed = _parse(show);
      if (parsed == null) continue;
      if (year != null && parsed.year != null && parsed.year != year) continue;
      results.add(parsed);
    }
    return results.take(20).toList();
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    final json = await _http.json(
      _endpoint('/shows/${candidate.id}'),
      maxBytes: 4 * 1024 * 1024,
    );
    if (json is! Map) throw const FormatException('TVmaze 没有返回剧集详情');
    final show = _parse(Map<String, dynamic>.from(json));
    if (show == null) throw const FormatException('TVmaze 剧集详情格式无效');
    final crew = await _crew(candidate.id);
    return MediaMetadata(
      id: show.id,
      mediaType: 'tv',
      title: show.title,
      overview: show.overview,
      year: show.year,
      genres: show.genres,
      rating: show.rating,
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      duration: show.duration,
      provider: id,
      language: show.language,
      countries: show.countries,
      people: crew,
      externalIds: show.externalIds,
      ratings: show.ratings,
    );
  }

  Future<List<MediaPerson>> _crew(int showId) async {
    try {
      final json = await _http.json(
        _endpoint('/shows/$showId/crew'),
        maxBytes: 4 * 1024 * 1024,
      );
      if (json is! List) return const [];
      final people = <MediaPerson>[];
      final seen = <String>{};
      for (final entry in json.whereType<Map>()) {
        final person = entry['person'];
        if (person is! Map) continue;
        final name = plainText(person['name']?.toString());
        final type = entry['type']?.toString() ?? '';
        if (name.isEmpty || !seen.add('$name:$type')) continue;
        if (people.length >= 24) break;
        people.add(
          MediaPerson(
            name: name,
            role: type,
            department: type.toLowerCase() == 'director'
                ? 'Directing'
                : 'Cast',
          ),
        );
      }
      return people;
    } catch (_) {
      // Crew data is a bonus; a failed lookup must not lose the title.
      return const [];
    }
  }

  MediaMetadata? _parse(Map json) {
    final id = (json['id'] as num?)?.toInt();
    final name = plainText(json['name']?.toString());
    if (id == null || id <= 0 || name.isEmpty) return null;
    final image = json['image'];
    final network = json['network'] ?? json['webChannel'];
    final average = json['rating'] is Map
        ? ((json['rating'] as Map)['average'] as num?)
        : null;
    final country = network is Map
        ? ((network['country'] as Map?)?['name'])?.toString()
        : null;
    return MediaMetadata(
      id: id,
      mediaType: 'tv',
      title: name,
      overview: plainText(json['summary']?.toString()),
      year: yearOf(json['premiered']?.toString()),
      genres: (json['genres'] as List? ?? [])
          .map((g) => g.toString())
          .where((g) => g.isNotEmpty)
          .toList(),
      rating: average?.toDouble(),
      posterUrl: image is Map ? image['original']?.toString() : null,
      backdropUrl: image is Map ? image['original']?.toString() : null,
      duration: ((json['runtime'] as num?)?.toDouble() ?? 0) * 60,
      provider: 'tvmaze',
      language: json['language']?.toString() ?? '',
      countries: [if (country != null && country.isNotEmpty) country],
      ratings: [
        if (average is num) MediaRating(source: 'TVmaze', value: average.toDouble()),
      ],
      externalIds: {
        if (json['externals'] is Map)
          for (final entry in (json['externals'] as Map).entries)
            if (entry.value != null && '${entry.value}'.isNotEmpty)
              entry.key.toString(): '${entry.value}',
      },
    );
  }
}
