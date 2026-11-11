import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'media_item.dart';
import 'media_metadata.dart';
import 'metadata_languages.dart';

String metadataSnapshot(MediaItem item) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'source': item.sourceId,
          'kind': item.kind.name,
          'title': item.title,
          'showTitle': item.showTitle,
          'overview': item.overview,
          'year': item.year,
          'posterUrl': item.posterUrl,
          'backdropUrl': item.backdropUrl,
          'aiAllowed': item.aiAllowed,
          'metadata': item.metadata?.toJson(),
        }),
      ),
    )
    .toString();

MediaMetadata metadataForLanguages(MediaItem item) =>
    item.metadata ??
    MediaMetadata(
      id: 0,
      provider: 'local',
      reviewed: false,
      mediaType: item.kind == MediaKind.episode ? 'episode' : item.kind.name,
      title: item.title,
      overview: item.overview,
      genres: item.genres,
      year: item.year,
    );

MediaMetadata retainLanguages(MediaMetadata fresh, MediaMetadata? previous) {
  if (previous == null || previous.localized.isEmpty) return fresh;
  if (identical(fresh, previous)) return fresh;
  if ((fresh.provider.startsWith('custom:') ||
          previous.provider.startsWith('custom:')) &&
      fresh.provider != 'local' &&
      previous.provider != 'local') {
    final freshId = fresh.externalIds['custom_id'] ?? '';
    final oldId = previous.externalIds['custom_id'] ?? '';
    if (fresh.provider != previous.provider ||
        freshId.isEmpty ||
        oldId.isEmpty ||
        freshId != oldId)
      return fresh;
  }
  if (fresh.id > 0 &&
      previous.id > 0 &&
      (fresh.id != previous.id ||
          fresh.mediaType != previous.mediaType ||
          fresh.provider != previous.provider))
    return fresh;
  for (final key in ['tmdb', 'imdb']) {
    if (fresh.externalIds[key]?.isNotEmpty == true &&
        previous.externalIds[key]?.isNotEmpty == true &&
        fresh.externalIds[key] != previous.externalIds[key])
      return fresh;
  }
  final texts = {...previous.localized};
  for (final entry in fresh.localized.entries) {
    texts[entry.key] = (texts[entry.key] ?? const LocalizedMetadata())
        .mergeSource(entry.value);
  }
  return fresh.withLanguages(
    texts,
    alternatives: {...previous.alternativeTitles, ...fresh.alternativeTitles},
    preferred: fresh.preferredLanguages.isNotEmpty
        ? fresh.preferredLanguages
        : previous.preferredLanguages,
  );
}

class MetadataLanguageDraft {
  const MetadataLanguageDraft({
    required this.itemId,
    required this.before,
    required this.metadata,
    this.generatedByModel = false,
  });
  final String itemId, before;
  final MediaMetadata metadata;
  final bool generatedByModel;
}
