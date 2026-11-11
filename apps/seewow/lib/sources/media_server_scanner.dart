import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import 'json_api.dart';

/// Jellyfin / Emby read-only catalog + direct-play URLs. No server writes.
class MediaServerScanner {
  Future<List<MediaItem>> scan(MediaSource source, String token) async {
    if (token.trim().isEmpty) throw const FormatException('请提供媒体服务器 API Key');
    final headers = {'X-Emby-Token': token.trim()};
    final api = JsonApi(Uri.parse(source.location), headers: headers);
    final items = <MediaItem>[];
    final seen = <String>{};
    const pageSize = 200;
    var offset = 0;
    try {
      for (var page = 0; page < 100; page++) {
        final path = source.username.isEmpty
            ? 'Items'
            : 'Users/${Uri.encodeComponent(source.username)}/Items';
        final json = await api.get(path, {
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Episode',
          'Fields': 'Overview,Genres,DateCreated,MediaStreams,MediaSources,People,ProviderIds,OriginalTitle,ProductionLocations',
          'StartIndex': '$offset',
          'Limit': '$pageSize',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        });
        final batch = json['Items'];
        if (batch is! List) throw const FormatException('媒体服务器响应缺少 Items 列表');
        var added = 0;
        for (final raw in batch) {
          if (raw is! Map<String, dynamic>)
            throw const FormatException('媒体条目格式无效');
          final id = raw['Id']?.toString() ?? '';
          if (id.isEmpty || !seen.add(id)) continue;
          added++;
          if (!['Movie', 'Episode'].contains(raw['Type'])) continue;
          final tags = raw['ImageTags'] as Map? ?? {};
          final user = raw['UserData'] as Map? ?? {};
          final duration =
              (raw['RunTimeTicks'] as num? ?? 0).toDouble() / 10000000;
          final position =
              (user['PlaybackPositionTicks'] as num? ?? 0).toDouble() /
              10000000;
          final streams = (raw['MediaStreams'] as List? ?? [])
              .whereType<Map>()
              .where((s) => s['Type'] == 'Video');
          final width = (streams.firstOrNull?['Width'] as num? ?? 0).toInt();
          final episode = raw['Type'] == 'Episode';
          final posterId = tags['Primary'] != null
              ? id
              : raw['SeriesId']?.toString();
          final backdropId =
              (raw['BackdropImageTags'] as List? ?? []).isNotEmpty
              ? id
              : raw['ParentBackdropItemId']?.toString();
          final mediaSources = (raw['MediaSources'] as List? ?? [])
              .whereType<Map>();
          items.add(
            MediaItem(
              id: '${source.id}:$id',
              sourceId: source.id,
              metadata: MediaMetadata(
                id: 0,
                provider: source.kind.name,
                reviewed: false,
                mediaType: episode ? 'episode' : 'movie',
                title: raw['Name'] as String? ?? '未命名',
                originalTitle: raw['OriginalTitle'] as String? ?? '',
                countries: (raw['ProductionLocations'] as List? ?? [])
                    .whereType<String>()
                    .toList(),
                people: (raw['People'] as List? ?? [])
                    .whereType<Map>()
                    .where((p) => p['Name'] is String)
                    .map(
                      (p) => MediaPerson(
                        name: p['Name'],
                        role: (p['Role'] ?? p['Type'] ?? '').toString(),
                        department: p['Type'] == 'Actor' ? 'Cast' : 'Crew',
                        id: p['Id']?.toString(),
                      ),
                    )
                    .toList(),
                ratings: [
                  if (raw['CommunityRating'] is num)
                    MediaRating(
                      source: '${source.kind.name} community',
                      value: (raw['CommunityRating'] as num).toDouble(),
                    ),
                  if (raw['CriticRating'] is num)
                    MediaRating(
                      source: '${source.kind.name} critics',
                      value: (raw['CriticRating'] as num).toDouble(),
                      scale: 100,
                    ),
                ],
                externalIds: (raw['ProviderIds'] as Map? ?? {}).map(
                  (k, v) => MapEntry(k.toString().toLowerCase(), v.toString()),
                ),
              ),
              kind: episode ? MediaKind.episode : MediaKind.movie,
              title: raw['Name'] as String? ?? '未命名',
              showTitle: episode ? raw['SeriesName'] as String? : null,
              season: (raw['ParentIndexNumber'] as num?)?.toInt(),
              episode: (raw['IndexNumber'] as num?)?.toInt(),
              year: (raw['ProductionYear'] as num?)?.toInt(),
              locator: api.uri('Videos/${Uri.encodeComponent(id)}/stream', {
                'static': 'true',
              }).toString(),
              posterUrl: posterId == null
                  ? null
                  : api.uri(
                      'Items/${Uri.encodeComponent(posterId)}/Images/Primary',
                      {'maxWidth': '600'},
                    ).toString(),
              backdropUrl: backdropId == null
                  ? null
                  : api.uri(
                      'Items/${Uri.encodeComponent(backdropId)}/Images/Backdrop/0',
                      {'maxWidth': '1440'},
                    ).toString(),
              overview: raw['Overview'] as String? ?? '',
              genres: (raw['Genres'] as List? ?? []).cast<String>(),
              rating: (raw['CommunityRating'] as num?)?.toDouble(),
              duration: duration,
              position: user['Played'] == true
                  ? (duration > 0 ? duration : 1)
                  : position,
              isFavorite: user['IsFavorite'] as bool? ?? false,
              addedAt: DateTime.tryParse(raw['DateCreated'] as String? ?? ''),
              quality: width >= 3800
                  ? '4K'
                  : width >= 1900
                  ? '1080p'
                  : width >= 1200
                  ? '720p'
                  : '',
              container:
                  (mediaSources.firstOrNull?['Container'] as String? ?? '')
                      .toUpperCase(),
              httpHeaders: headers,
            ),
          );
        }
        offset += batch.length;
        final total = (json['TotalRecordCount'] as num?)?.toInt();
        if (batch.isEmpty && total != null && total > offset)
          throw const FormatException('服务器提前返回空页，未覆盖原片库');
        if (batch.isEmpty ||
            (total != null && offset >= total) ||
            (total == null && batch.length < pageSize))
          return items;
        if (added == 0) throw const FormatException('服务器重复返回同一页，已停止扫描并保留原片库');
      }
      throw const FormatException('片库超过本轮 20,000 条扫描上限，未覆盖原片库');
    } finally {
      api.close();
    }
  }
}
