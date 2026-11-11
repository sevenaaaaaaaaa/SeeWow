import 'media_item.dart';

class FilmCollection {
  FilmCollection({
    required this.id,
    required this.name,
    required this.itemIds,
    required this.createdAt,
    this.description = '',
  });
  final String id;
  final String name;
  final List<String> itemIds;
  final DateTime createdAt;
  final String description;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'itemIds': itemIds,
    'createdAt': createdAt.toIso8601String(),
    'description': description,
  };
  factory FilmCollection.fromJson(Map<String, dynamic> j) => FilmCollection(
    id: j['id'] as String,
    name: j['name'] as String,
    itemIds: (j['itemIds'] as List).cast<String>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    description: j['description'] as String? ?? '',
  );
}

class TasteProfile {
  final Set<String> genres = {};
  final Set<String> dislikedIds = {};
  final Set<String> watchlist = {};
  final Map<String, DateTime> lastPlayed = {};
  Map<String, dynamic> toJson() => {
    'genres': genres.toList(),
    'dislikedIds': dislikedIds.toList(),
    'watchlist': watchlist.toList(),
    'lastPlayed': lastPlayed.map((k, v) => MapEntry(k, v.toIso8601String())),
  };
  void read(Map<String, dynamic> j) {
    genres
      ..clear()
      ..addAll((j['genres'] as List? ?? []).cast<String>());
    dislikedIds
      ..clear()
      ..addAll((j['dislikedIds'] as List? ?? []).cast<String>());
    watchlist
      ..clear()
      ..addAll((j['watchlist'] as List? ?? []).cast<String>());
    lastPlayed
      ..clear()
      ..addAll(
        (j['lastPlayed'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, DateTime.parse(v as String)),
        ),
      );
  }
}

enum LibrarySort { recent, title, rating, year }

enum WatchFilter { all, unwatched, watching, watched, watchlist, favorites }

/// Shared by the library, command palette and agent: filters compose.
class LibraryQuery {
  const LibraryQuery({
    this.text = '',
    this.genre,
    this.sourceId,
    this.kind,
    this.watch = WatchFilter.all,
    this.sort = LibrarySort.recent,
  });
  final String text;
  final String? genre;
  final String? sourceId;
  final MediaKind? kind;
  final WatchFilter watch;
  final LibrarySort sort;
  List<MediaItem> apply(List<MediaItem> items, TasteProfile taste) {
    final terms = text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    final result = items.where((i) {
      final haystack =
          '${i.title} ${i.metadata?.title ?? ''} ${i.metadata?.multilingualSearchText ?? ''} ${i.showTitle ?? ''} ${i.year ?? ''} ${i.genres.join(' ')} ${i.quality} ${i.overview}'
              .toLowerCase();
      if (!terms.every(haystack.contains)) return false;
      if (genre != null && !i.genres.contains(genre)) return false;
      if (sourceId != null && i.sourceId != sourceId) return false;
      if (kind != null && i.kind != kind) return false;
      return switch (watch) {
        WatchFilter.all => true,
        WatchFilter.unwatched => i.position <= 30 && !i.watched,
        WatchFilter.watching => i.position > 30 && !i.watched,
        WatchFilter.watched => i.watched,
        WatchFilter.watchlist => taste.watchlist.contains(i.id),
        WatchFilter.favorites => i.isFavorite,
      };
    }).toList();
    result.sort((a, b) {
      final order = switch (sort) {
        LibrarySort.recent => (b.addedAt ?? DateTime(1970)).compareTo(
          a.addedAt ?? DateTime(1970),
        ),
        LibrarySort.title => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
        LibrarySort.rating => (b.rating ?? -1).compareTo(a.rating ?? -1),
        LibrarySort.year => (b.year ?? 0).compareTo(a.year ?? 0),
      };
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return result;
  }
}

class FilmPick {
  const FilmPick(this.item, this.score, this.reason);
  final MediaItem item;
  final double score;
  final String reason;
}

class RecommendationEngine {
  /// Explainable offline ranking. Never presented as a language model.
  List<FilmPick> recommend(
    List<MediaItem> library,
    TasteProfile taste, {
    String prompt = '',
    int limit = 12,
  }) {
    final weights = <String, double>{for (final g in taste.genres) g: 4};
    for (final i in library) {
      if (!i.isFavorite && !i.watched && i.position < 30) continue;
      for (final g in i.genres) {
        weights[g] = (weights[g] ?? 0) + (i.isFavorite ? 2 : 1);
      }
    }
    final q = prompt.toLowerCase();
    final requested = <String>{};
    for (final g in library.expand((i) => i.genres).toSet()) {
      if (q.contains(g.toLowerCase())) requested.add(g);
    }
    const moodGenres = {
      '轻松': ['喜剧', '动画'],
      '烧脑': ['悬疑', '科幻'],
      '太空': ['科幻'],
      '治愈': ['喜剧', '家庭'],
      '紧张': ['惊悚', '悬疑'],
    };
    for (final entry in moodGenres.entries) {
      if (q.contains(entry.key)) requested.addAll(entry.value);
    }
    final minuteMatch = RegExp(r'(\d+)\s*(分钟|min)').firstMatch(q);
    final maxMinutes = minuteMatch == null ? null : int.parse(minuteMatch[1]!);
    final picks = <FilmPick>[];
    for (final i in library) {
      if (i.kind != MediaKind.movie && i.kind != MediaKind.episode) continue;
      if (taste.dislikedIds.contains(i.id) || i.watched) continue;
      if (requested.isNotEmpty && !i.genres.any(requested.contains)) continue;
      // Unknown duration cannot satisfy a time budget.
      if (maxMinutes != null &&
          (i.duration <= 0 || i.duration > maxMinutes * 60))
        continue;
      final matches = i.genres.where((g) => (weights[g] ?? 0) > 0).toList();
      var score =
          (i.rating ?? 5) +
          i.genres.fold<double>(0, (s, g) => s + (weights[g] ?? 0));
      if (taste.watchlist.contains(i.id)) score += 2;
      if (i.position > 30) score -= 2;
      final reason = requested.isNotEmpty
          ? '符合「${i.genres.where(requested.contains).join(' / ')}」'
          : matches.isNotEmpty
          ? '根据你偏爱的${matches.join('、')}'
          : i.rating != null
          ? '片库中评分 ${i.rating!.toStringAsFixed(1)}，尚未看完'
          : '从尚未看过的片库中发现';
      picks.add(FilmPick(i, score, reason));
    }
    picks.sort((a, b) {
      final order = b.score.compareTo(a.score);
      return order == 0 ? a.item.id.compareTo(b.item.id) : order;
    });
    // A series occupies one recommendation slot, rather than flooding the list.
    final seen = <String>{};
    return picks
        .where(
          (p) => seen.add(
            p.item.kind == MediaKind.episode
                ? 'show:${p.item.showTitle ?? p.item.title}'
                : 'movie:${p.item.title.toLowerCase().replaceAll(RegExp(r"[^\w\u4e00-\u9fff]"), "")}:${p.item.year}',
          ),
        )
        .take(limit)
        .toList();
  }
}

class LibraryAudit {
  LibraryAudit(List<MediaItem> items) {
    final groups = <String, List<MediaItem>>{};
    for (final i in items) {
      if (i.kind != MediaKind.audio &&
          (i.posterUrl == null || i.overview.isEmpty))
        missingMetadata.add(i);
      final title = (i.showTitle ?? i.title).toLowerCase().replaceAll(
        RegExp(r'[^\w\u4e00-\u9fff]'),
        '',
      );
      final key =
          '$title:${i.artist}:${i.album}:${i.year}:${i.season}:${i.episode}';
      groups.putIfAbsent(key, () => []).add(i);
    }
    duplicates.addAll(groups.values.where((g) => g.length > 1));
  }
  final List<MediaItem> missingMetadata = [];
  final List<List<MediaItem>> duplicates = [];
}
