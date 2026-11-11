import 'dart:io';
import 'dart:convert';

import 'package:xml/xml.dart';

import '../domain/media_metadata.dart';

/// Read the sidecars already produced by a NAS or an existing scraper.
class NfoInfo {
  const NfoInfo({
    this.adult,
    this.title,
    this.showTitle,
    this.year,
    this.season,
    this.episode,
    this.overview = '',
    this.genres = const [],
    this.rating,
    this.duration = 0,
    this.originalTitle = '',
    this.originalLanguage = '',
    this.countries = const [],
    this.people = const [],
    this.ratings = const [],
    this.externalIds = const {},
    this.poster,
    this.backdrop,
    this.directory,
  });
  final bool? adult;
  final String? title, showTitle;
  final int? year, season, episode;
  final String overview;
  final List<String> genres;
  final double? rating;
  final double duration;
  final String originalTitle, originalLanguage;
  final List<String> countries;
  final List<MediaPerson> people;
  final List<MediaRating> ratings;
  final Map<String, String> externalIds;
  final String? poster, backdrop;
  final Uri? directory;

  MediaMetadata asMetadata({
    required String fallbackTitle,
    required String mediaType,
    NfoInfo? inherit,
  }) => MediaMetadata(
    id: 0,
    provider: 'nfo',
    adult: adult ?? inherit?.adult,
    reviewed: false,
    mediaType: mediaType,
    title: title ?? fallbackTitle,
    year: year ?? inherit?.year,
    overview: overview.isEmpty ? inherit?.overview ?? '' : overview,
    genres: genres.isEmpty ? inherit?.genres ?? const [] : genres,
    rating: rating ?? inherit?.rating,
    ratings: ratings.isEmpty ? inherit?.ratings ?? const [] : ratings,
    people: people.isEmpty ? inherit?.people ?? const [] : people,
    originalTitle: originalTitle,
    originalLanguage: originalLanguage.isEmpty
        ? inherit?.originalLanguage ?? ''
        : originalLanguage,
    countries: countries.isEmpty ? inherit?.countries ?? const [] : countries,
    externalIds: {...?inherit?.externalIds, ...externalIds},
    posterUrl: directory == null ? null : artwork(poster, directory!),
    backdropUrl: directory == null ? null : artwork(backdrop, directory!),
    duration: duration,
  );

  static String? artwork(String? reference, Uri directory) {
    if (reference == null || reference.trim().isEmpty) return null;
    final ref = Uri.tryParse(reference.trim());
    if (ref == null || ref.userInfo.isNotEmpty) return null;
    if (['http', 'https'].contains(ref.scheme) && ref.host.isNotEmpty)
      return ref.toString();
    if (ref.hasScheme || ref.hasAuthority || ref.path.startsWith('/'))
      return null;
    final result = directory.resolveUri(ref);
    if (!result.path.startsWith(directory.path)) return null;
    return result.scheme == 'file' ? result.toFilePath() : result.toString();
  }

  static NfoInfo parse(String text, {Uri? directory}) {
    if (text.length > 2 * 1024 * 1024 ||
        RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text))
      throw const FormatException('NFO 不允许外部实体或超大内容');
    final root = XmlDocument.parse(text).rootElement;
    if (![
      'movie',
      'tvshow',
      'episodedetails',
      'musicvideo',
      'album',
      'artist',
    ].contains(root.name.local))
      throw const FormatException('不支持的 NFO 类型');
    String? value(String name) {
      final value = root.getElement(name)?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final ratings =
        root.getElement('ratings')?.findElements('rating').toList() ?? [];
    final preferred =
        ratings.where((r) => r.getAttribute('default') == 'true').firstOrNull ??
        ratings.firstOrNull;
    final rawRating = double.tryParse(
      preferred?.getElement('value')?.innerText ?? value('rating') ?? '',
    );
    final scale = double.tryParse(preferred?.getAttribute('max') ?? '') ?? 10;
    final rating =
        rawRating == null ||
            !rawRating.isFinite ||
            scale <= 0 ||
            rawRating < 0 ||
            rawRating > scale
        ? null
        : rawRating / scale * 10;
    final scores = <MediaRating>[];
    for (final r in ratings) {
      final v = double.tryParse(r.getElement('value')?.innerText ?? '');
      if (v == null) continue;
      final score = MediaRating(
        source: r.getAttribute('name') ?? 'NFO',
        value: v,
        scale: double.tryParse(r.getAttribute('max') ?? '') ?? 10,
        votes: int.tryParse(r.getElement('votes')?.innerText ?? ''),
      );
      if (score.valid) scores.add(score);
    }
    if (scores.isEmpty && rating != null)
      scores.add(MediaRating(source: 'NFO', value: rating));
    final people = <MediaPerson>[
      for (final actor in root.findElements('actor'))
        if ((actor.getElement('name')?.innerText.trim() ?? '').isNotEmpty)
          MediaPerson(
            name: actor.getElement('name')!.innerText.trim(),
            role: actor.getElement('role')?.innerText.trim() ?? '',
          ),
      for (final tag in ['director', 'credits', 'artist'])
        for (final person in root.findElements(tag))
          if (person.innerText.trim().isNotEmpty)
            MediaPerson(
              name: person.innerText.trim(),
              role: tag == 'director'
                  ? 'Director'
                  : tag == 'credits'
                  ? 'Writer'
                  : 'Artist',
              department: 'Crew',
            ),
    ];
    return NfoInfo(
      adult: switch (value('adult')?.toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => null,
      },
      title: value('title') ?? value('name'),
      directory: directory,
      showTitle: value('showtitle'),
      year: int.tryParse(value('year') ?? ''),
      season: int.tryParse(value('season') ?? ''),
      episode: int.tryParse(value('episode') ?? ''),
      overview: value('plot') ?? value('outline') ?? '',
      genres: root
          .findElements('genre')
          .map((e) => e.innerText.trim())
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList(),
      rating: rating != null && rating >= 0 && rating <= 10 ? rating : null,
      originalTitle: value('originaltitle') ?? '',
      originalLanguage: value('originallanguage') ?? '',
      countries: root
          .findElements('country')
          .map((e) => e.innerText.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      people: people,
      ratings: scores,
      externalIds: {
        for (final id in root.findElements('uniqueid'))
          if (id.getAttribute('type') != null && id.innerText.trim().isNotEmpty)
            id.getAttribute('type')!: id.innerText.trim(),
      },
      poster: root
          .findElements('thumb')
          .where(
            (e) =>
                e.getAttribute('aspect') == null ||
                e.getAttribute('aspect') == 'poster',
          )
          .firstOrNull
          ?.innerText
          .trim(),
      backdrop: root
          .getElement('fanart')
          ?.getElement('thumb')
          ?.innerText
          .trim(),
      duration:
          (double.tryParse(value('runtime') ?? '') ?? 0).clamp(0, 100000) * 60,
    );
  }

  static Future<NfoInfo?> read(List<File> candidates) async {
    for (final f in candidates) {
      if (!await f.exists()) continue;
      try {
        if (await f.length() > 2 * 1024 * 1024) continue;
        return parse(decode(await f.readAsBytes()), directory: f.parent.uri);
      } catch (_) {
        /* Bad sidecars do not prevent playing the original file. */
      }
    }
    return null;
  }

  static String decode(List<int> bytes) {
    if (bytes.length > 2 * 1024 * 1024)
      throw const FormatException('NFO 超过读取上限');
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      if (bytes.length.isOdd) throw const FormatException('UTF-16 NFO 长度无效');
      final little = bytes[0] == 255;
      return String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2)
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      ]);
    }
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  }
}
