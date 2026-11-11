import 'metadata_languages.dart';

class MediaPerson {
  const MediaPerson({
    required this.name,
    this.role = '',
    this.department = 'Cast',
    this.id,
    this.imageUrl,
  });
  final String name, role, department;
  final String? id, imageUrl;
  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'department': department,
    'id': id,
    'imageUrl': imageUrl,
  };
  factory MediaPerson.fromJson(Map<String, dynamic> j) => MediaPerson(
    name: j['name'] as String? ?? '',
    role: j['role'] as String? ?? '',
    department: j['department'] as String? ?? 'Cast',
    id: j['id']?.toString(),
    imageUrl: j['imageUrl'] as String?,
  );
}

class MediaRating {
  const MediaRating({
    required this.source,
    required this.value,
    this.scale = 10,
    this.votes,
  });
  final String source;
  final double value, scale;
  final int? votes;
  bool get valid =>
      value.isFinite &&
      scale.isFinite &&
      scale > 0 &&
      value >= 0 &&
      value <= scale;
  Map<String, dynamic> toJson() => {
    'source': source,
    'value': value,
    'scale': scale,
    'votes': votes,
  };
  factory MediaRating.fromJson(Map<String, dynamic> j) => MediaRating(
    source: j['source'] as String? ?? 'Unknown',
    value: (j['value'] as num).toDouble(),
    scale: (j['scale'] as num? ?? 10).toDouble(),
    votes: (j['votes'] as num?)?.toInt(),
  );
}

class MediaArtwork {
  const MediaArtwork({
    required this.url,
    this.type = 'poster',
    this.language = '',
    this.width,
    this.height,
  });
  final String url, type, language;
  final int? width, height;
  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type,
    'language': language,
    'width': width,
    'height': height,
  };
  factory MediaArtwork.fromJson(Map<String, dynamic> j) => MediaArtwork(
    url: j['url'] as String,
    type: j['type'] as String? ?? 'poster',
    language: j['language'] as String? ?? '',
    width: j['width'] as int?,
    height: j['height'] as int?,
  );
}

/// Source-tagged metadata. Only reviewed matches are locked across rescans.
class MediaMetadata {
  const MediaMetadata({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
    this.adult,
    this.overview = '',
    this.genres = const [],
    this.rating,
    this.posterUrl,
    this.backdropUrl,
    this.duration = 0,
    this.replaceArtwork = false,
    this.provider = 'tmdb',
    this.reviewed = true,
    this.originalTitle = '',
    this.originalLanguage = '',
    this.language = '',
    this.countries = const [],
    this.people = const [],
    this.ratings = const [],
    this.artworks = const [],
    this.externalIds = const {},
    this.notes = const [],
    this.localized = const {},
    this.alternativeTitles = const {},
    this.preferredLanguages = const [],
    this.generatedCover = const {},
  });
  final int id;
  final String mediaType, title, overview;

  /// Explicit provider content flag; absent means unclassified, never safe.
  final bool? adult;
  final int? year;
  final List<String> genres;
  final double? rating;
  final String? posterUrl, backdropUrl;
  final double duration;
  final bool replaceArtwork;
  final String provider, originalTitle, originalLanguage, language;
  final bool reviewed;
  final List<String> countries, notes;
  final List<MediaPerson> people;
  final List<MediaRating> ratings;
  final List<MediaArtwork> artworks;
  final Map<String, String> externalIds;
  final Map<String, LocalizedMetadata> localized;
  final Map<String, List<String>> alternativeTitles;
  final List<String> preferredLanguages;

  /// AI artwork provenance, separate from provider metadata and ratings.
  final Map<String, String> generatedCover;
  String get multilingualSearchText => [
    originalTitle,
    for (final text in localized.values) '${text.title} ${text.overview}',
    for (final titles in alternativeTitles.values) titles.join(' '),
  ].join(' ');
  Map<String, dynamic> toJson() => {
    'id': id,
    'mediaType': mediaType,
    'title': title,
    'year': year,
    'adult': adult,
    'overview': overview,
    'genres': genres,
    'rating': rating,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'duration': duration,
    'replaceArtwork': replaceArtwork,
    'provider': provider,
    'reviewed': reviewed,
    'originalTitle': originalTitle,
    'originalLanguage': originalLanguage,
    'language': language,
    'countries': countries,
    'people': people.map((p) => p.toJson()).toList(),
    'ratings': ratings.map((r) => r.toJson()).toList(),
    'artworks': artworks.map((a) => a.toJson()).toList(),
    'externalIds': externalIds,
    'notes': notes,
    'localized': localized.map((key, value) => MapEntry(key, value.toJson())),
    'alternativeTitles': alternativeTitles,
    'preferredLanguages': preferredLanguages,
    'generatedCover': generatedCover,
  };
  factory MediaMetadata.fromJson(Map<String, dynamic> j) => MediaMetadata(
    id: j['id'] as int,
    mediaType: j['mediaType'] as String,
    title: j['title'] as String,
    year: j['year'] as int?,
    adult: j['adult'] as bool?,
    overview: j['overview'] as String? ?? '',
    genres: (j['genres'] as List? ?? []).cast<String>(),
    rating: (j['rating'] as num?)?.toDouble(),
    posterUrl: j['posterUrl'] as String?,
    backdropUrl: j['backdropUrl'] as String?,
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    replaceArtwork: j['replaceArtwork'] as bool? ?? false,
    provider: j['provider'] as String? ?? 'tmdb',
    reviewed: j['reviewed'] != false,
    originalTitle: j['originalTitle'] as String? ?? '',
    originalLanguage: j['originalLanguage'] as String? ?? '',
    language: j['language'] as String? ?? '',
    countries: (j['countries'] as List? ?? []).cast<String>(),
    notes: (j['notes'] as List? ?? []).cast<String>(),
    people: (j['people'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MediaPerson.fromJson)
        .toList(),
    ratings: (j['ratings'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MediaRating.fromJson)
        .where((r) => r.valid)
        .toList(),
    artworks: (j['artworks'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MediaArtwork.fromJson)
        .toList(),
    externalIds: (j['externalIds'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ),
    localized: (j['localized'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k.toString(),
        LocalizedMetadata.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    alternativeTitles: (j['alternativeTitles'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), (v as List).cast<String>()),
    ),
    preferredLanguages: (j['preferredLanguages'] as List? ?? []).cast<String>(),
    generatedCover: (j['generatedCover'] as Map? ?? {}).cast<String, String>(),
  );
  MediaMetadata withArtwork(bool replace) =>
      MediaMetadata.fromJson({...toJson(), 'replaceArtwork': replace});
  MediaMetadata withImages({String? poster, String? backdrop}) =>
      MediaMetadata.fromJson({
        ...toJson(),
        'posterUrl': poster ?? posterUrl,
        'backdropUrl': backdrop ?? backdropUrl,
      });
  MediaMetadata withLanguages(
    Map<String, LocalizedMetadata> texts, {
    Map<String, List<String>>? alternatives,
    List<String>? preferred,
  }) => MediaMetadata.fromJson({
    ...toJson(),
    'localized': texts.map((k, v) => MapEntry(k, v.toJson())),
    'alternativeTitles': alternatives ?? alternativeTitles,
    'preferredLanguages': preferred ?? preferredLanguages,
  });
}
