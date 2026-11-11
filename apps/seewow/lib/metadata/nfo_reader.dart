import 'dart:io';

import 'package:xml/xml.dart';

/// Read the sidecars already produced by a NAS or an existing scraper.
class NfoInfo {
  const NfoInfo({
    this.title,
    this.showTitle,
    this.year,
    this.season,
    this.episode,
    this.overview = '',
    this.genres = const [],
    this.rating,
    this.duration = 0,
  });
  final String? title, showTitle;
  final int? year, season, episode;
  final String overview;
  final List<String> genres;
  final double? rating;
  final double duration;
  static NfoInfo parse(String text) {
    if (text.length > 2 * 1024 * 1024 ||
        RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text))
      throw const FormatException('NFO 不允许外部实体或超大内容');
    final root = XmlDocument.parse(text).rootElement;
    if (!['movie', 'tvshow', 'episodedetails'].contains(root.name.local))
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
    final rating = double.tryParse(
      preferred?.getElement('value')?.innerText ?? value('rating') ?? '',
    );
    return NfoInfo(
      title: value('title'),
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
      duration:
          (double.tryParse(value('runtime') ?? '') ?? 0).clamp(0, 100000) * 60,
    );
  }

  static Future<NfoInfo?> read(List<File> candidates) async {
    for (final f in candidates) {
      if (!await f.exists()) continue;
      try {
        if (await f.length() > 2 * 1024 * 1024) continue;
        return parse(await f.readAsString());
      } catch (_) {
        /* Bad sidecars do not prevent playing the original file. */
      }
    }
    return null;
  }
}
