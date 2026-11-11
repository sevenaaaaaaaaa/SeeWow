/// A reviewed metadata match. Kept with the item so rescanning does not undo it.
class MediaMetadata {
  const MediaMetadata({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
    this.overview = '',
    this.genres = const [],
    this.rating,
    this.posterUrl,
    this.backdropUrl,
    this.duration = 0,
    this.replaceArtwork = false,
  });
  final int id;
  final String mediaType, title, overview;
  final int? year;
  final List<String> genres;
  final double? rating;
  final String? posterUrl, backdropUrl;
  final double duration;
  final bool replaceArtwork;
  Map<String, dynamic> toJson() => {
    'id': id,
    'mediaType': mediaType,
    'title': title,
    'year': year,
    'overview': overview,
    'genres': genres,
    'rating': rating,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'duration': duration,
    'replaceArtwork': replaceArtwork,
  };
  factory MediaMetadata.fromJson(Map<String, dynamic> j) => MediaMetadata(
    id: j['id'] as int,
    mediaType: j['mediaType'] as String,
    title: j['title'] as String,
    year: j['year'] as int?,
    overview: j['overview'] as String? ?? '',
    genres: (j['genres'] as List? ?? []).cast<String>(),
    rating: (j['rating'] as num?)?.toDouble(),
    posterUrl: j['posterUrl'] as String?,
    backdropUrl: j['backdropUrl'] as String?,
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    replaceArtwork: j['replaceArtwork'] as bool? ?? false,
  );
  MediaMetadata withArtwork(bool replace) =>
      MediaMetadata.fromJson({...toJson(), 'replaceArtwork': replace});
}
