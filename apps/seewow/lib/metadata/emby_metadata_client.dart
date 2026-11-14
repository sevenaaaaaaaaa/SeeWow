import '../domain/media_metadata.dart';
import 'metadata_source.dart';
import 'metadata_transport.dart';

/// Native metadata from a Jellyfin or Emby server the user already connected.
///
/// This is the catalogue the server itself curated, including its own artwork,
/// so it wins over a public lookup for titles that live on that server.
class EmbyMetadataSource implements MetadataSource {
  EmbyMetadataSource({
    required this.base,
    required this.token,
    this.userId = '',
    String kind = 'jellyfin',
    this.serverName = '',
    MetadataTransport? transport,
  }) : _kind = kind == 'emby' ? 'emby' : 'jellyfin',
       _http = transport ?? MetadataTransport(timeout: const Duration(seconds: 20));

  final Uri base;
  final String token, userId, serverName;
  final String _kind;
  final MetadataTransport _http;

  static const _fields =
      'Overview,Genres,People,ProviderIds,ProductionYear,CommunityRating,'
      'RunTimeTicks,OriginalTitle,ProductionLocations,ImageTags,BackdropImageTags';

  @override
  String get id => _kind;

  @override
  String get label => serverName.isEmpty
      ? (_kind == 'emby' ? 'Emby 服务器' : 'Jellyfin 服务器')
      : '$serverName（$_kind 服务器）';

  @override
  bool get seriesOnly => false;

  @override
  void close() => _http.close();

  Uri _endpoint(String path, [Map<String, String> query = const {}]) {
    final root = base.toString().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root/$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Map<String, String> get _headers => {'X-Emby-Token': token};

  String _itemsPath() => userId.trim().isEmpty
      ? 'Items'
      : 'Users/${Uri.encodeComponent(userId.trim())}/Items';

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final json = await _http.json(
      _endpoint(_itemsPath(), {
        'Recursive': 'true',
        'SearchTerm': term,
        'IncludeItemTypes': series ? 'Series' : 'Movie',
        'Fields': _fields,
        'StartIndex': '${(page - 1) * 20}',
        'Limit': '20',
      }),
      headers: _headers,
      allowLan: true,
    );
    if (json is! Map) throw const FormatException('服务器没有返回有效的搜索结果');
    final items = json['Items'];
    if (items is! List) throw const FormatException('服务器响应缺少 Items 列表');
    final results = <MediaMetadata>[];
    for (final raw in items.whereType<Map>()) {
      final parsed = _parse(Map<String, dynamic>.from(raw));
      if (parsed == null) continue;
      if (year != null && parsed.year != null && parsed.year != year) continue;
      results.add(parsed);
    }
    return results;
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    final serverId = candidate.externalIds[id] ?? candidate.externalIds['guid'];
    final path = serverId == null || serverId.isEmpty
        ? '${_itemsPath()}/${candidate.id}'
        : '${_itemsPath()}/${Uri.encodeComponent(serverId)}';
    final json = await _http.json(
      _endpoint(path, {'Fields': _fields}),
      headers: _headers,
      allowLan: true,
    );
    if (json is! Map) throw const FormatException('服务器没有返回条目详情');
    final full = _parse(Map<String, dynamic>.from(json));
    if (full == null) throw const FormatException('服务器条目格式无效');
    return full;
  }

  /// The server's own id as a stable positive int, because [MediaMetadata.id]
  /// is an int while Jellyfin ids are GUIDs. The GUID itself is kept in
  /// [MediaMetadata.externalIds], which is what [details] reads back.
  int? _stableId(String guid) {
    final hex = guid.replaceAll('-', '');
    if (hex.length < 8) return null;
    final value = int.tryParse(hex.substring(hex.length - 8), radix: 16);
    if (value == null) return null;
    final positive = value & 0x7fffffff;
    return positive == 0 ? null : positive;
  }

  String? _image(String itemId, String type, int width) {
    if (itemId.isEmpty) return null;
    final root = base.toString().replaceAll(RegExp(r'/+$'), '');
    return '$root/Items/${Uri.encodeComponent(itemId)}/Images/$type'
        '?maxWidth=$width';
  }

  MediaMetadata? _parse(Map<String, dynamic> json) {
    final guid = json['Id']?.toString() ?? '';
    final id = _stableId(guid);
    final title = plainText(json['Name']?.toString());
    if (id == null || title.isEmpty) return null;
    final type = json['Type']?.toString() ?? '';
    final mediaType = switch (type) {
      'Series' => 'tv',
      'Episode' => 'episode',
      _ => 'movie',
    };
    final ticks = (json['RunTimeTicks'] as num? ?? 0).toDouble();
    final imageTags = json['ImageTags'] as Map? ?? {};
    final backdrops = (json['BackdropImageTags'] as List? ?? []);
    final providerIds = (json['ProviderIds'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString().toLowerCase(), value.toString()),
    );
    final rating = (json['CommunityRating'] as num?)?.toDouble();
    return MediaMetadata(
      id: id,
      mediaType: mediaType,
      title: title,
      originalTitle: plainText(json['OriginalTitle']?.toString()),
      overview: plainText(json['Overview']?.toString()),
      year: (json['ProductionYear'] as num?)?.toInt(),
      genres: (json['Genres'] as List? ?? [])
          .map((g) => g.toString())
          .where((g) => g.isNotEmpty)
          .toList(),
      rating: rating,
      posterUrl: imageTags['Primary'] != null ? _image(guid, 'Primary', 600) : null,
      backdropUrl: backdrops.isNotEmpty
          ? _image(guid, 'Backdrop/0', 1440)
          : null,
      duration: ticks / 10000000,
      provider: _kind,
      countries: (json['ProductionLocations'] as List? ?? [])
          .whereType<String>()
          .toList(),
      people: [
        for (final person in (json['People'] as List? ?? []).whereType<Map>())
          if (person['Name'] is String && (person['Name'] as String).isNotEmpty)
            MediaPerson(
              name: person['Name'] as String,
              role: (person['Role'] ?? person['Type'] ?? '').toString(),
              department: person['Type'] == 'Actor' ? 'Cast' : 'Crew',
              id: person['Id']?.toString(),
            ),
      ],
      ratings: [
        if (rating != null)
          MediaRating(source: _kind == 'emby' ? 'Emby 社区评分' : 'Jellyfin 社区评分', value: rating),
      ],
      externalIds: {...providerIds, _kind: guid},
    );
  }
}
