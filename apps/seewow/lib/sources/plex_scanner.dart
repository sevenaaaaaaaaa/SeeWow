import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import 'json_api.dart';

class PlexScanner {
  Future<List<MediaItem>> scan(MediaSource source, String token) async {
    if (token.isEmpty) throw const FormatException('请提供 Plex Token');
    final headers = {'X-Plex-Token': token};
    final api = JsonApi(Uri.parse(source.location), headers: headers);
    final items = <MediaItem>[];
    final ids = <String>{};
    try {
      final root = await api.get('library/sections');
      final sections = (root['MediaContainer'] as Map?)?['Directory'];
      if (sections is! List) throw const FormatException('Plex 资料库响应无效');
      for (final section in sections.whereType<Map>()) {
        if (!['movie', 'show'].contains(section['type'])) continue;
        final key = section['key']?.toString() ?? '';
        if (!RegExp(r'^\d+$').hasMatch(key))
          throw const FormatException('Plex 资料库标识无效');
        var offset = 0;
        for (var page = 0; page < 100; page++) {
          final response = await api.get('library/sections/$key/all', {
            'type': section['type'] == 'show' ? '4' : '1',
            'X-Plex-Container-Start': '$offset',
            'X-Plex-Container-Size': '200',
          });
          final container = response['MediaContainer'];
          if (container is! Map) throw const FormatException('Plex 分页格式无效');
          final list =
              container['Metadata'] ?? (container['size'] == 0 ? [] : null);
          if (list is! List) throw const FormatException('Plex 未返回媒体列表');
          final total = (container['totalSize'] as num?)?.toInt();
          if (list.isEmpty && total != null && offset < total)
            throw const FormatException('Plex 分页中断；原片库保留');
          for (final m in list.whereType<Map>()) {
            final id = m['ratingKey']?.toString() ?? '';
            if (id.isEmpty || !ids.add(id))
              throw const FormatException('Plex 返回无效或重复媒体标识');
            final media = (m['Media'] as List? ?? [])
                .whereType<Map>()
                .firstOrNull;
            final part = (media?['Part'] as List? ?? [])
                .whereType<Map>()
                .firstOrNull;
            final partKey = part?['key'] as String?;
            if (partKey == null) continue;
            Uri safePath(String path) {
              if (!path.startsWith('/') ||
                  path.startsWith('//') ||
                  path.contains('?') ||
                  path.contains('#') ||
                  path.contains('..'))
                throw const FormatException('Plex 返回了无效的媒体路径');
              return api.uri(path);
            }

            final episode = m['type'] == 'episode';
            final duration = (m['duration'] as num? ?? 0).toDouble() / 1000;
            final width = (media?['width'] as num? ?? 0).toInt();
            items.add(
              MediaItem(
                id: '${source.id}:$id',
                sourceId: source.id,
                metadata: MediaMetadata(
                  id: 0,
                  provider: 'plex',
                  reviewed: false,
                  mediaType: episode ? 'episode' : 'movie',
                  title: m['title'] as String? ?? '未命名',
                  originalTitle: m['originalTitle'] as String? ?? '',
                  people: [
                    for (final field in ['Role', 'Director', 'Writer'])
                      for (final person
                          in (m[field] as List? ?? []).whereType<Map>())
                        if (person['tag'] is String)
                          MediaPerson(
                            name: person['tag'],
                            role: (person['role'] ?? field).toString(),
                            department: field == 'Role' ? 'Cast' : 'Crew',
                          ),
                  ],
                  ratings: [
                    if (m['rating'] is num)
                      MediaRating(
                        source: 'Plex critics',
                        value: (m['rating'] as num).toDouble(),
                      ),
                    if (m['audienceRating'] is num)
                      MediaRating(
                        source: 'Plex audience',
                        value: (m['audienceRating'] as num).toDouble(),
                      ),
                  ],
                  countries: (m['Country'] as List? ?? [])
                      .whereType<Map>()
                      .map((c) => c['tag'].toString())
                      .toList(),
                  externalIds: {
                    for (final guid
                        in (m['Guid'] as List? ?? []).whereType<Map>())
                      if (guid['id'] is String &&
                          Uri.tryParse(guid['id'])?.hasScheme == true)
                        Uri.parse(guid['id']).scheme: Uri.parse(guid['id'])
                            .host,
                  },
                ),
                kind: episode ? MediaKind.episode : MediaKind.movie,
                title: m['title'] as String? ?? '未命名',
                showTitle: episode ? m['grandparentTitle'] as String? : null,
                season: (m['parentIndex'] as num?)?.toInt(),
                episode: (m['index'] as num?)?.toInt(),
                year: (m['year'] as num?)?.toInt(),
                locator: safePath(partKey).toString(),
                posterUrl: (m['thumb'] ?? m['grandparentThumb']) is String
                    ? safePath((m['thumb'] ?? m['grandparentThumb']) as String)
                          .toString()
                    : null,
                backdropUrl: m['art'] is String
                    ? safePath(m['art'] as String).toString()
                    : null,
                overview: m['summary'] as String? ?? '',
                genres: (m['Genre'] as List? ?? [])
                    .whereType<Map>()
                    .map((g) => g['tag'].toString())
                    .toList(),
                rating: (m['audienceRating'] as num? ?? m['rating'] as num?)
                    ?.toDouble(),
                duration: duration,
                position: (m['viewCount'] as num? ?? 0) > 0
                    ? duration
                    : (m['viewOffset'] as num? ?? 0).toDouble() / 1000,
                quality: width >= 3800
                    ? '4K'
                    : width >= 1900
                    ? '1080p'
                    : media?['videoResolution']?.toString() ?? '',
                container: media?['container']?.toString().toUpperCase() ?? '',
                fileSize: (part?['size'] as num? ?? 0).toInt(),
                addedAt: m['addedAt'] is num
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (m['addedAt'] as num).toInt() * 1000,
                      )
                    : null,
                httpHeaders: headers,
              ),
            );
          }
          offset += list.length;
          if (list.isEmpty ||
              total != null && offset >= total ||
              total == null && list.length < 200)
            break;
          if (page == 99) throw const FormatException('Plex 片库过大，请拆分来源；原片库保留');
        }
      }
      return items;
    } finally {
      api.close();
    }
  }
}
