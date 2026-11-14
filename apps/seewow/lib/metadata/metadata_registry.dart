import '../domain/media_metadata.dart';
import 'metadata_source.dart';

/// Field names used as keys in [MediaMetadata.fieldSources].
///
/// The names are stable on purpose: they end up in the saved library file, so a
/// later version can still tell which catalogue answered for each field.
class MetadataFields {
  static const title = 'title';
  static const originalTitle = 'originalTitle';
  static const overview = 'overview';
  static const year = 'year';
  static const genres = 'genres';
  static const rating = 'rating';
  static const poster = 'poster';
  static const backdrop = 'backdrop';
  static const duration = 'duration';
  static const people = 'people';
  static const countries = 'countries';
  static const externalIds = 'externalIds';
}

String providerLabel(String provider) {
  switch (provider) {
    case 'tmdb':
      return 'TMDB';
    case 'tvmaze':
      return 'TVmaze';
    case 'bangumi':
      return 'Bangumi';
    case 'jellyfin':
      return 'Jellyfin';
    case 'emby':
      return 'Emby';
    case 'nfo':
      return 'NFO';
    case 'custom':
      return '自定义刮削';
    case '':
      return '未知来源';
    default:
      return provider;
  }
}

/// Records [label] as the source of every field this record actually carries.
///
/// A field left empty gets no entry: claiming a source for a blank overview is
/// exactly the kind of quiet lie this map exists to prevent.
MediaMetadata annotateFields(MediaMetadata metadata, String label) {
  final sources = <String, String>{...metadata.fieldSources};
  void tag(String field, bool present) {
    if (present) sources[field] = label;
  }

  tag(MetadataFields.title, metadata.title.isNotEmpty);
  tag(MetadataFields.originalTitle, metadata.originalTitle.isNotEmpty);
  tag(MetadataFields.overview, metadata.overview.isNotEmpty);
  tag(MetadataFields.year, metadata.year != null);
  tag(MetadataFields.genres, metadata.genres.isNotEmpty);
  tag(MetadataFields.rating, metadata.rating != null);
  tag(MetadataFields.poster, (metadata.posterUrl ?? '').isNotEmpty);
  tag(MetadataFields.backdrop, (metadata.backdropUrl ?? '').isNotEmpty);
  tag(MetadataFields.duration, metadata.duration > 0);
  tag(MetadataFields.people, metadata.people.isNotEmpty);
  tag(MetadataFields.countries, metadata.countries.isNotEmpty);
  tag(MetadataFields.externalIds, metadata.externalIds.isNotEmpty);
  return metadata.withFieldSources(sources);
}

/// Fills the gaps of [primary] with [fallback], and keeps both provenances.
///
/// Only empty fields are taken from the fallback: the service the user picked
/// always wins where it actually answered.
MediaMetadata mergeMetadata(MediaMetadata primary, MediaMetadata fallback) {
  final label = providerLabel(fallback.provider);
  // The primary is labelled first: a field it answered must never be credited
  // to the catalogue that merely failed to add anything.
  final labelled = annotateFields(primary, providerLabel(primary.provider));
  final sources = <String, String>{...labelled.fieldSources};
  Map<String, dynamic> fill(Map<String, dynamic> target, Map<String, dynamic> other) {
    for (final entry in other.entries) {
      final current = target[entry.key];
      final missing = current == null ||
          (current is String && current.isEmpty) ||
          (current is List && current.isEmpty) ||
          (current is Map && current.isEmpty) ||
          (current is num && current == 0);
      if (missing && entry.value != null) target[entry.key] = entry.value;
    }
    return target;
  }

  final json = Map<String, dynamic>.from(labelled.toJson());
  final fallbackJson = fallback.toJson();
  // Everything except identity and the provenance map itself may be filled in.
  final rest = Map<String, dynamic>.from(fallbackJson)
    ..remove('id')
    ..remove('mediaType')
    ..remove('fieldSources');
  fill(json, rest);

  void tag(String field, Object? value) {
    if (value == null) return;
    if (value is String && value.isEmpty) return;
    if (value is List && value.isEmpty) return;
    if (value is Map && value.isEmpty) return;
    if (value is num && value == 0) return;
    sources.putIfAbsent(field, () => label);
  }

  tag(MetadataFields.title, json['title']);
  tag(MetadataFields.originalTitle, json['originalTitle']);
  tag(MetadataFields.overview, json['overview']);
  tag(MetadataFields.year, json['year']);
  tag(MetadataFields.genres, json['genres']);
  tag(MetadataFields.rating, json['rating']);
  tag(MetadataFields.poster, json['posterUrl']);
  tag(MetadataFields.backdrop, json['backdropUrl']);
  tag(MetadataFields.duration, json['duration']);
  tag(MetadataFields.people, json['people']);
  tag(MetadataFields.countries, json['countries']);
  tag(MetadataFields.externalIds, json['externalIds']);
  json['fieldSources'] = sources;
  return MediaMetadata.fromJson(json);
}

/// One query against one catalogue, kept so the UI can say what happened.
class MetadataAttempt {
  const MetadataAttempt({
    required this.sourceId,
    required this.label,
    required this.count,
    this.error,
  });
  final String sourceId, label;
  final int count;
  final String? error;
  bool get ok => error == null;
}

class MetadataSearchOutcome {
  const MetadataSearchOutcome({
    required this.results,
    required this.attempts,
    this.answeredBy,
  });
  final List<MediaMetadata> results;
  final List<MetadataAttempt> attempts;

  /// The catalogue that produced the first usable result.
  final String? answeredBy;

  bool get usedFallback {
    if (answeredBy == null) return false;
    final firstOk = attempts.where((a) => a.ok && a.count > 0).firstOrNull;
    return firstOk != null && firstOk.sourceId != attempts.first.sourceId;
  }

  /// A one-line, honest summary of which catalogues were asked.
  String get summary {
    if (attempts.isEmpty) return '没有可用的数据源';
    final parts = <String>[
      for (final attempt in attempts)
        attempt.ok
            ? '${attempt.label} ${attempt.count} 条'
            : '${attempt.label} 失败（${attempt.error}）',
    ];
    return parts.join(' · ');
  }
}

/// The catalogues this app can ask, in the order a fallback chain walks them.
///
/// A catalogue that cannot answer for the current media type is skipped rather
/// than asked and reported as an error — TVmaze has no films, and saying so is
/// cheaper than a failed request.
class MetadataRegistry {
  MetadataRegistry(Iterable<MetadataSource> sources)
    : sources = List<MetadataSource>.unmodifiable(sources);

  final List<MetadataSource> sources;

  MetadataSource? byId(String id) => sources.where((s) => s.id == id).firstOrNull;

  List<MetadataSource> applicable({required bool series}) =>
      [for (final source in sources) if (!source.seriesOnly || series) source];

  /// Searches [preferred] first, then falls back down the chain until
  /// [minimum] results exist. Failed catalogues are recorded, not thrown, so
  /// one dead service never empties the dialog.
  Future<MetadataSearchOutcome> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
    int minimum = 3,
    String? preferred,
  }) async {
    final usable = applicable(series: series);
    if (usable.isEmpty) {
      throw const FormatException('没有适用于此类型的数据源');
    }
    final ordered = <MetadataSource>[
      if (preferred != null)
        for (final source in usable)
          if (source.id == preferred) source,
      for (final source in usable)
        if (source.id != preferred) source,
    ];
    final attempts = <MetadataAttempt>[];
    final results = <MediaMetadata>[];
    final seen = <String>{};
    String? answeredBy;
    Object? firstError;
    var answered = false;
    for (final source in ordered) {
      final label = source.label;
      try {
        final found = await source.search(
          query,
          series: series,
          year: year,
          page: page,
        );
        attempts.add(
          MetadataAttempt(
            sourceId: source.id,
            label: label,
            count: found.length,
          ),
        );
        for (final item in found) {
          final key = item.id > 0
              ? '${item.provider}:${item.id}'
              : '${item.title.toLowerCase()}:${item.year ?? 0}';
          if (!seen.add(key)) continue;
          results.add(annotateFields(item, providerLabel(source.id)));
        }
        if (found.isNotEmpty && answeredBy == null) {
          answeredBy = source.id;
          answered = true;
        }
        if (results.length >= minimum) break;
      } catch (error) {
        firstError ??= error;
        attempts.add(
          MetadataAttempt(
            sourceId: source.id,
            label: label,
            count: 0,
            error: _message(error),
          ),
        );
      }
    }
    if (results.isEmpty && !answered && firstError != null) throw firstError;
    return MetadataSearchOutcome(
      results: results,
      attempts: attempts,
      answeredBy: answeredBy,
    );
  }

  /// Details from the catalogue that produced [candidate], with every other
  /// search result of the same work used to fill whatever it left blank.
  Future<MediaMetadata> details(
    MediaMetadata candidate, {
    MetadataSource? source,
    Iterable<MediaMetadata> supplements = const [],
  }) async {
    final chosen = source ?? byId(candidate.provider);
    if (chosen == null) {
      throw FormatException('找不到资料源「${providerLabel(candidate.provider)}」');
    }
    var full = await chosen.details(candidate);
    full = annotateFields(full, providerLabel(chosen.id));
    for (final extra in supplements) {
      if (extra.provider == full.provider) continue;
      if (extra.title.toLowerCase() != full.title.toLowerCase() &&
          (extra.originalTitle.isEmpty ||
              extra.originalTitle.toLowerCase() != full.title.toLowerCase())) {
        continue;
      }
      if (extra.year != null && full.year != null && extra.year != full.year) {
        continue;
      }
      full = mergeMetadata(full, extra);
    }
    return full;
  }

  void close() {
    for (final source in sources) {
      source.close();
    }
  }

  static String _message(Object error) {
    final text = error.toString();
    return text.startsWith('FormatException: ')
        ? text.substring('FormatException: '.length)
        : text;
  }
}
