enum MediaKind { movie, episode, other }

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
  });

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

  double get progress => duration <= 0 ? 0 : (position / duration).clamp(0, 1);
  bool get watched => duration > 0 && position / duration > 0.92;
  int get remainingSeconds => (duration - position).clamp(0, duration).round();

  String get badgeText {
    if (quality.isNotEmpty) return quality;
    return container.toUpperCase();
  }

  String get displayTitle {
    if (kind == MediaKind.episode && season != null && episode != null) {
      return '${showTitle ?? title}  S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}';
    }
    return title;
  }

  MediaItem copyWith({double? position, double? duration, String? posterUrl, String? backdropUrl, String? overview, double? rating, List<String>? genres, bool? isFavorite, Map<String, String>? httpHeaders}) => MediaItem(
        id: id,
        sourceId: sourceId,
        kind: kind,
        title: title,
        locator: locator,
        showTitle: showTitle,
        season: season,
        episode: episode,
        year: year,
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
        'id': id, 'sourceId': sourceId, 'kind': kind.name, 'title': title, 'locator': locator,
        'showTitle': showTitle, 'season': season, 'episode': episode, 'year': year,
        'quality': quality, 'posterUrl': posterUrl, 'backdropUrl': backdropUrl,
        'overview': overview, 'rating': rating, 'genres': genres, 'duration': duration,
        'position': position, 'addedAt': addedAt?.toIso8601String(), 'fileSize': fileSize,
        'container': container, 'isFavorite': isFavorite, 'httpHeaders': httpHeaders,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        sourceId: j['sourceId'] as String,
        kind: MediaKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => MediaKind.other),
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
        addedAt: j['addedAt'] != null ? DateTime.tryParse(j['addedAt'] as String) : null,
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        container: (j['container'] as String?) ?? '',
        isFavorite: (j['isFavorite'] as bool?) ?? false,
        httpHeaders: (j['httpHeaders'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      );
}

enum SourceKind { local, smb, webdav, emby, jellyfin, plex, dlna, iptv }

class MediaSource {
  MediaSource({required this.id, required this.kind, required this.name, required this.location, this.username = '', this.enabled = true, this.lastScan});
  final String id;
  final SourceKind kind;
  final String name;
  final String location;
  final String username;
  final bool enabled;
  final DateTime? lastScan;

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'name': name, 'location': location, 'username': username, 'enabled': enabled, 'lastScan': lastScan?.toIso8601String()};
  factory MediaSource.fromJson(Map<String, dynamic> j) => MediaSource(
        id: j['id'] as String,
        kind: SourceKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => SourceKind.local),
        name: j['name'] as String,
        location: j['location'] as String,
        username: (j['username'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
        lastScan: j['lastScan'] != null ? DateTime.tryParse(j['lastScan'] as String) : null,
      );
}
