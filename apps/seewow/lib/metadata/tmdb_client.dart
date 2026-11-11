import '../domain/media_metadata.dart';
import '../sources/json_api.dart';
import '../sources/native_bridge.dart';

class TmdbClient {
  TmdbClient(String token, {Uri? base})
    : _api = JsonApi(
        base ?? Uri.parse('https://api.themoviedb.org/3'),
        headers: {'Authorization': 'Bearer ${token.trim()}'},
        maxBytes: 2 * 1024 * 1024,
      ) {
    if (token.trim().isEmpty)
      throw const FormatException('请先配置 TMDB API Read Access Token');
  }
  final JsonApi _api;
  static const tokenKey = 'metadata.tmdb.readToken';
  static Future<TmdbClient> configured() async =>
      TmdbClient(await NativeBridge.secretRead(tokenKey) ?? '');
  static Future<void> configure(String token) async {
    if (token.trim().isEmpty)
      throw const FormatException('请填写 TMDB API Read Access Token');
    await NativeBridge.secretWrite(tokenKey, token.trim());
  }

  static String? imageUrl(Object? path, {bool backdrop = false}) =>
      path is String && RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(path)
      ? 'https://image.tmdb.org/t/p/${backdrop ? 'w1280' : 'w500'}$path'
      : null;
  Future<List<MediaMetadata>> search(
    String query, {
    bool series = false,
  }) async {
    if (query.trim().isEmpty) return [];
    final type = series ? 'tv' : 'movie';
    final json = await _api.get('search/$type', {
      'query': query.trim(),
      'language': 'zh-CN',
      'include_adult': 'false',
      'page': '1',
    });
    final results = json['results'];
    if (results is! List) throw const FormatException('TMDB 没有返回有效的搜索结果');
    return results
        .whereType<Map<String, dynamic>>()
        .where((j) => j['id'] is num)
        .take(12)
        .map((j) => _parse(j, type))
        .toList();
  }

  Future<MediaMetadata> details(MediaMetadata candidate) async {
    final j = await _api.get('${candidate.mediaType}/${candidate.id}', {
      'language': 'zh-CN',
    });
    if (j['id'] != candidate.id) throw const FormatException('TMDB 详情与所选条目不一致');
    return _parse(j, candidate.mediaType);
  }

  MediaMetadata _parse(Map<String, dynamic> j, String type) => MediaMetadata(
    id: (j['id'] as num).toInt(),
    mediaType: type,
    title:
        (j[type == 'tv' ? 'name' : 'title'] ??
                j[type == 'tv' ? 'original_name' : 'original_title'] ??
                '未命名')
            .toString(),
    year: int.tryParse(
      (j[type == 'tv' ? 'first_air_date' : 'release_date'] as String? ?? '')
          .split('-')
          .first,
    ),
    overview: j['overview'] as String? ?? '',
    genres: (j['genres'] as List? ?? [])
        .whereType<Map>()
        .map((g) => g['name']?.toString() ?? '')
        .where((g) => g.isNotEmpty)
        .toList(),
    rating: (j['vote_count'] as num? ?? 0) > 0
        ? (j['vote_average'] as num?)?.toDouble()
        : null,
    posterUrl: imageUrl(j['poster_path']),
    backdropUrl: imageUrl(j['backdrop_path'], backdrop: true),
    duration: type == 'movie' ? (j['runtime'] as num? ?? 0).toDouble() * 60 : 0,
  );
  void close() => _api.close();
}
