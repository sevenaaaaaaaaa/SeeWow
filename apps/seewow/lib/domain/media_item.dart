import 'media_metadata.dart';

enum MediaKind { movie, episode, other, audio }

class MediaItem {
  MediaItem({
    required this.id,
    required this.sourceId,
    required this.kind,
    required this.title,
    required this.locator,
    this.showTitle,
    this.season,
    this.episode,
    this.year,
    this.quality = '',
    this.posterUrl,
    this.backdropUrl,
    this.overview = '',
    this.rating,
    this.genres = const [],
    this.duration = 0,
    this.position = 0,
    this.addedAt,
    this.fileSize = 0,
    this.container = '',
    this.isFavorite = false,
    this.httpHeaders = const {},
    this.metadata,
    this.sourceRef,
    this.artist = '',
    this.album = '',
    this.aiAllowed = true,
  });

  final MediaMetadata? metadata;
  final String? sourceRef;
  final String artist, album;
  final bool aiAllowed;
  bool get hasGeneratedCover =>
      posterUrl != null && posterUrl == metadata?.generatedCover['path'];

  final String id;
  final String sourceId;
  final MediaKind kind;
  final String title;
  final String locator;
  final String? showTitle;
  final int? season;
  final int? episode;
  final int? year;
  final String quality;
  final String? posterUrl;
  final String? backdropUrl;
  final String overview;
  final double? rating;
  final List<String> genres;
  final double duration;
  final double position;
  final DateTime? addedAt;
  final int fileSize;
  final String container;
  final bool isFavorite;

  /// Auth headers for HTTP(S) sources (WebDAV / Emby). Empty for local files.
  final Map<String, String> httpHeaders;

  Map<String, String> artworkHeaders(String? url) {
    final media = Uri.tryParse(locator), art = Uri.tryParse(url ?? '');
    return media != null &&
            art != null &&
            ['http', 'https'].contains(art.scheme) &&
            ['http', 'https'].contains(media.scheme) &&
            media.origin == art.origin
        ? httpHeaders
        : const {};
  }

  MediaItem withMetadata(MediaMetadata match) => copyWith(
    metadata:
        hasGeneratedCover && (!match.replaceArtwork || match.posterUrl == null)
        ? MediaMetadata.fromJson({
            ...match.toJson(),
            'generatedCover': metadata!.generatedCover,
          })
        : match,
    title: kind != MediaKind.episode || match.mediaType == 'episode'
        ? match.title
        : title,
    showTitle: showTitle,
    year: match.year,
    overview: match.overview.isEmpty ? overview : match.overview,
    genres: match.genres.isEmpty ? genres : match.genres,
    rating: match.rating,
    posterUrl: match.replaceArtwork || posterUrl == null
        ? match.posterUrl
        : posterUrl,
    backdropUrl: match.replaceArtwork || backdropUrl == null
        ? match.backdropUrl
        : backdropUrl,
    duration:
        (kind == MediaKind.movie || match.mediaType == 'episode') &&
            duration <= 0 &&
            match.duration > 0
        ? match.duration
        : duration,
  );

  double get progress => duration <= 0 ? 0 : (position / duration).clamp(0, 1);
  bool get watched => duration > 0 && position / duration > 0.92;
  int get remainingSeconds => (duration - position).clamp(0, duration).round();

  String get badgeText {
    if (quality.isNotEmpty) return quality;
    return container.toUpperCase();
  }

  String get libraryTitle => kind == MediaKind.episode
      ? (metadata?.mediaType == 'tv' ? metadata!.title : showTitle ?? title)
      : metadata?.title ?? title;

  String get displayTitle {
    if (kind == MediaKind.episode && season != null && episode != null) {
      return '${metadata?.mediaType == 'tv' ? metadata!.title : showTitle ?? title}  S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}';
    }
    return title;
  }

  MediaItem copyWith({
    bool clearMetadata = false,
    String? locator,
    String? title,
    String? showTitle,
    int? year,
    MediaMetadata? metadata,
    double? position,
    double? duration,
    String? posterUrl,
    String? backdropUrl,
    String? overview,
    double? rating,
    List<String>? genres,
    bool? isFavorite,
    Map<String, String>? httpHeaders,
  }) => MediaItem(
    id: id,
    sourceId: sourceId,
    kind: kind,
    title: title ?? this.title,
    locator: locator ?? this.locator,
    sourceRef: sourceRef,
    artist: artist,
    album: album,
    aiAllowed: aiAllowed,
    showTitle: showTitle ?? this.showTitle,
    season: season,
    episode: episode,
    year: year ?? this.year,
    metadata: clearMetadata ? null : metadata ?? this.metadata,
    quality: quality,
    posterUrl: posterUrl ?? this.posterUrl,
    backdropUrl: backdropUrl ?? this.backdropUrl,
    overview: overview ?? this.overview,
    rating: rating ?? this.rating,
    genres: genres ?? this.genres,
    duration: duration ?? this.duration,
    position: position ?? this.position,
    addedAt: addedAt,
    fileSize: fileSize,
    container: container,
    isFavorite: isFavorite ?? this.isFavorite,
    httpHeaders: httpHeaders ?? this.httpHeaders,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceRef': sourceRef,
    'artist': artist,
    'album': album,
    'aiAllowed': aiAllowed,
    'sourceId': sourceId,
    'kind': kind.name,
    'title': title,
    'locator': sourceRef == null
        ? locator
        : Uri(
            scheme: 'seewow',
            host: 'source',
            path: '/$sourceId',
            queryParameters: {'ref': sourceRef!},
          ).toString(),
    'showTitle': showTitle,
    'season': season,
    'episode': episode,
    'year': year,
    'quality': quality,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'overview': overview,
    'rating': rating,
    'genres': genres,
    'duration': duration,
    'position': position,
    'addedAt': addedAt?.toIso8601String(),
    'fileSize': fileSize,
    'container': container,
    'isFavorite': isFavorite,
    'metadata': metadata?.toJson(),
    'httpHeaders': sourceRef == null
        ? httpHeaders.wherePublic()
        : <String, String>{},
  };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    sourceRef: j['sourceRef'] as String?,
    artist: j['artist'] as String? ?? '',
    album: j['album'] as String? ?? '',
    aiAllowed: j['aiAllowed'] != false,
    metadata: j['metadata'] == null
        ? null
        : MediaMetadata.fromJson(j['metadata'] as Map<String, dynamic>),
    id: j['id'] as String,
    sourceId: j['sourceId'] as String,
    kind: MediaKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => MediaKind.other,
    ),
    title: j['title'] as String,
    locator: j['locator'] as String,
    showTitle: j['showTitle'] as String?,
    season: j['season'] as int?,
    episode: j['episode'] as int?,
    year: j['year'] as int?,
    quality: (j['quality'] as String?) ?? '',
    posterUrl: j['posterUrl'] as String?,
    backdropUrl: j['backdropUrl'] as String?,
    overview: (j['overview'] as String?) ?? '',
    rating: (j['rating'] as num?)?.toDouble(),
    genres: (j['genres'] as List?)?.cast<String>() ?? const [],
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    position: (j['position'] as num?)?.toDouble() ?? 0,
    addedAt: j['addedAt'] != null
        ? DateTime.tryParse(j['addedAt'] as String)
        : null,
    fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
    container: (j['container'] as String?) ?? '',
    isFavorite: (j['isFavorite'] as bool?) ?? false,
    httpHeaders:
        (j['httpHeaders'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {},
  );
}

enum SourceKind {
  local,
  smb,
  webdav,
  emby,
  jellyfin,
  plex,
  dlna,
  iptv,
  openlist,
  synology,
  navidrome,
  bridge,
}

class MediaSource {
  MediaSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    this.username = '',
    this.enabled = true,
    this.lastScan,
    this.providerId = '',
    this.rootPath = '/',
  });
  final String id;
  final SourceKind kind;
  final String name;
  final String location;
  final String username;
  final bool enabled;
  final DateTime? lastScan;
  final String providerId, rootPath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'location': location,
    'username': username,
    'enabled': enabled,
    'lastScan': lastScan?.toIso8601String(),
    'providerId': providerId,
    'rootPath': rootPath,
  };
  factory MediaSource.fromJson(Map<String, dynamic> j) => MediaSource(
    id: j['id'] as String,
    kind: SourceKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => SourceKind.local,
    ),
    name: j['name'] as String,
    location: j['location'] as String,
    username: (j['username'] as String?) ?? '',
    enabled: (j['enabled'] as bool?) ?? true,
    providerId: j['providerId'] as String? ?? '',
    rootPath: j['rootPath'] as String? ?? '/',
    lastScan: j['lastScan'] != null
        ? DateTime.tryParse(j['lastScan'] as String)
        : null,
  );
}

/// Authentication is restored from the credential store, never from library JSON.
extension PublicMediaHeaders on Map<String, String> {
  Map<String, String> wherePublic() => Map.fromEntries(
    entries.where(
      (e) => !{
        'authorization',
        'proxy-authorization',
        'cookie',
        'set-cookie',
        'x-emby-token',
        'x-mediabrowser-token',
        'x-api-key',
        'x-plex-token',
      }.contains(e.key.toLowerCase()),
    ),
  );
}
