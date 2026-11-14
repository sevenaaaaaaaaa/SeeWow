import 'media_item.dart';

/// One shelf the home feed can show without anybody curating it.
///
/// The engine is deliberately offline and deterministic: the same library
/// always produces the same shelves in the same order, so a test can pin it.
enum AutoCollectionKind {
  show,
  rating,
  quality,
  runtime,
  genre,
  decade,
  country,
  person,
  hiddenGem,
}

class AutoCollection {
  const AutoCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.items,
    required this.total,
  });

  final String id;
  final String title;
  final String subtitle;
  final AutoCollectionKind kind;
  final List<MediaItem> items;

  /// How many entries the dimension matched, before the per-shelf cap. Ranking
  /// uses this, so a genre with 40 films outranks one with 12.
  final int total;
}

/// Builds home shelves from the library itself.
///
/// Rules that keep the feed honest:
/// * an episode never appears twice — a series is folded into its shows;
/// * a shelf needs [minItems] distinct entries, otherwise it is noise;
/// * documentaries keep their dedicated shelf on the home feed, so the genre
///   dimension skips them here;
/// * shelves are interleaved by kind, so the feed does not open with five
///   genre rows in a row.
class CollectionEngine {
  const CollectionEngine({
    this.minItems = 4,
    this.maxCollections = 10,
    this.perCollection = 12,
  });

  final int minItems;
  final int maxCollections;
  final int perCollection;

  /// Documentary has its own fixed shelf; the auto feed never duplicates it.
  static const _reservedGenres = {'纪录片', 'documentary', 'Documentary'};

  List<AutoCollection> build(List<MediaItem> library, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final entries = _entries(library);
    if (entries.isEmpty) return const [];

    final byKind = <AutoCollectionKind, List<AutoCollection>>{};
    void add(AutoCollectionKind kind, List<AutoCollection> shelves) {
      if (shelves.isEmpty) return;
      byKind.putIfAbsent(kind, () => []).addAll(shelves);
    }

    add(AutoCollectionKind.show, _shows(entries));
    add(AutoCollectionKind.hiddenGem, _hiddenGems(entries, reference));
    add(AutoCollectionKind.rating, _ratings(entries));
    add(AutoCollectionKind.quality, _qualities(entries));
    add(AutoCollectionKind.runtime, _runtimes(entries));
    add(AutoCollectionKind.genre, _genres(entries));
    add(AutoCollectionKind.decade, _decades(entries));
    add(AutoCollectionKind.country, _countries(entries));
    add(AutoCollectionKind.person, _people(entries));

    // Interleave: strongest of each kind first, then the next of each kind.
    final order = [
      AutoCollectionKind.show,
      AutoCollectionKind.hiddenGem,
      AutoCollectionKind.rating,
      AutoCollectionKind.genre,
      AutoCollectionKind.quality,
      AutoCollectionKind.decade,
      AutoCollectionKind.runtime,
      AutoCollectionKind.country,
      AutoCollectionKind.person,
    ];
    for (final shelves in byKind.values) {
      shelves.sort(_byStrength);
    }
    final result = <AutoCollection>[];
    var round = 0;
    while (result.length < maxCollections) {
      var progressed = false;
      for (final kind in order) {
        final shelves = byKind[kind];
        if (shelves == null || round >= shelves.length) continue;
        progressed = true;
        result.add(shelves[round]);
        if (result.length >= maxCollections) break;
      }
      if (!progressed) break;
      round++;
    }
    return result;
  }

  /// One entry per film and one per series, newest first.
  List<MediaItem> _entries(List<MediaItem> library) {
    final shows = <String, MediaItem>{};
    final entries = <MediaItem>[];
    for (final item in library) {
      if (item.kind == MediaKind.audio) continue;
      final show = item.showTitle?.trim() ?? '';
      if (item.kind == MediaKind.episode && show.isNotEmpty) {
        final kept = shows[show];
        if (kept == null || (item.season ?? 0) < (kept.season ?? 0)) {
          shows[show] = item;
        }
        continue;
      }
      entries.add(item);
    }
    entries.addAll(shows.values);
    entries.sort((a, b) {
      final order = (b.addedAt ?? DateTime(1970)).compareTo(
        a.addedAt ?? DateTime(1970),
      );
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return entries;
  }

  int _byStrength(AutoCollection a, AutoCollection b) {
    final order = b.total.compareTo(a.total);
    return order == 0 ? a.id.compareTo(b.id) : order;
  }

  AutoCollection? _shelf(
    AutoCollectionKind kind,
    String id,
    String title,
    String subtitle,
    List<MediaItem> items,
  ) {
    final seen = <String>{};
    final picked = <MediaItem>[];
    for (final item in items) {
      final show = item.showTitle?.trim() ?? '';
      final key = show.isNotEmpty ? 'show:$show' : 'movie:${item.id}';
      if (seen.add(key)) picked.add(item);
      if (picked.length >= perCollection) break;
    }
    if (picked.length < minItems) return null;
    return AutoCollection(
      id: id,
      title: title,
      subtitle: subtitle,
      kind: kind,
      items: picked,
      total: items.length,
    );
  }

  /// One card per series, not one shelf per series: a feed of five
  /// single-series rows would push every other dimension off the screen.
  List<AutoCollection> _shows(List<MediaItem> entries) {
    final episodes = entries
        .where((i) => i.kind == MediaKind.episode)
        .where((i) => (i.showTitle ?? '').trim().isNotEmpty)
        .toList();
    final shelf = _shelf(
      AutoCollectionKind.show,
      'shows',
      '剧集连看',
      '${episodes.map((i) => i.showTitle!.trim()).toSet().length} 部剧集 · 接着看下一集',
      episodes,
    );
    return shelf == null ? const [] : [shelf];
  }

  List<AutoCollection> _hiddenGems(List<MediaItem> entries, DateTime now) {
    final cutoff = now.subtract(const Duration(days: 30));
    final gems = entries
        .where((i) => (i.rating ?? 0) >= 7.5 && !i.watched && i.position < 30)
        .where((i) => (i.addedAt ?? now).isBefore(cutoff))
        .toList();
    final shelf = _shelf(
      AutoCollectionKind.hiddenGem,
      'hidden-gems',
      '高分冷门',
      '评分不低，你一直没点开',
      gems,
    );
    return shelf == null ? const [] : [shelf];
  }

  List<AutoCollection> _ratings(List<MediaItem> entries) {
    final shelves = <AutoCollection>[];
    final top = entries.where((i) => (i.rating ?? 0) >= 8).toList();
    final good = entries
        .where((i) => (i.rating ?? 0) >= 7 && (i.rating ?? 0) < 8)
        .toList();
    for (final (id, title, subtitle, items) in [
      ('rating:top', '高分精选', '8.0 分以上', top),
      ('rating:solid', '值得一看', '7.0 – 8.0 分', good),
    ]) {
      final shelf = _shelf(
        AutoCollectionKind.rating,
        id,
        title,
        subtitle,
        items,
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  List<AutoCollection> _qualities(List<MediaItem> entries) {
    bool has(MediaItem i, List<String> marks) {
      final q = i.quality.toLowerCase();
      return marks.any(q.contains);
    }

    final shelves = <AutoCollection>[];
    for (final (id, title, subtitle, marks) in [
      ('quality:4k', '4K 画质', '2160p / UHD 片源', ['4k', '2160', 'uhd']),
      ('quality:hdr', 'HDR 专场', '高动态范围片源', ['hdr', 'dolby vision', 'dv']),
    ]) {
      final shelf = _shelf(
        AutoCollectionKind.quality,
        id,
        title,
        subtitle,
        entries.where((i) => has(i, marks)).toList(),
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  List<AutoCollection> _runtimes(List<MediaItem> entries) {
    final shelves = <AutoCollection>[];
    for (final (id, title, subtitle, min, max) in [
      ('runtime:short', '一小时以内', '适合睡前的一部', 0.0, 3600.0),
      ('runtime:mid', '一小时出头', '60 – 100 分钟', 3600.0, 6000.0),
      ('runtime:long', '长片马拉松', '100 分钟以上', 6000.0, double.infinity),
    ]) {
      final shelf = _shelf(
        AutoCollectionKind.runtime,
        id,
        title,
        subtitle,
        entries
            .where((i) => i.duration > min && i.duration <= max)
            .toList(),
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  List<AutoCollection> _genres(List<MediaItem> entries) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in entries) {
      for (final genre in item.genres) {
        final name = genre.trim();
        if (name.isEmpty || _reservedGenres.contains(name)) continue;
        grouped.putIfAbsent(name, () => []).add(item);
      }
    }
    final shelves = <AutoCollection>[];
    for (final entry in grouped.entries) {
      final shelf = _shelf(
        AutoCollectionKind.genre,
        'genre:${entry.key}',
        entry.key,
        '${entry.value.length} 部同类影片',
        entry.value,
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  List<AutoCollection> _decades(List<MediaItem> entries) {
    final grouped = <int, List<MediaItem>>{};
    for (final item in entries) {
      final year = item.year;
      if (year == null || year < 1900) continue;
      grouped.putIfAbsent((year ~/ 10) * 10, () => []).add(item);
    }
    final shelves = <AutoCollection>[];
    for (final entry in grouped.entries) {
      final shelf = _shelf(
        AutoCollectionKind.decade,
        'decade:${entry.key}',
        '${entry.key} 年代',
        '那个十年的选择',
        entry.value,
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  List<AutoCollection> _countries(List<MediaItem> entries) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in entries) {
      for (final country in item.metadata?.countries ?? const <String>[]) {
        final name = country.trim();
        if (name.isEmpty) continue;
        grouped.putIfAbsent(name, () => []).add(item);
      }
    }
    final shelves = <AutoCollection>[];
    for (final entry in grouped.entries) {
      final shelf = _shelf(
        AutoCollectionKind.country,
        'country:${entry.key}',
        '${entry.key}制造',
        '${entry.value.length} 部',
        entry.value,
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }

  /// Directors first: a director's shelf is a better promise than an actor's.
  List<AutoCollection> _people(List<MediaItem> entries) {
    final grouped = <String, List<MediaItem>>{};
    for (final item in entries) {
      final people = item.metadata?.people ?? const [];
      final directors = people
          .where((p) => p.department.toLowerCase() == 'directing')
          .map((p) => p.name.trim())
          .where((n) => n.isNotEmpty);
      final chosen = directors.isNotEmpty
          ? directors
          : people
                .where((p) => p.department.toLowerCase() == 'acting')
                .map((p) => p.name.trim())
                .where((n) => n.isNotEmpty)
                .take(2);
      for (final name in chosen) {
        grouped.putIfAbsent(name, () => []).add(item);
      }
    }
    final shelves = <AutoCollection>[];
    for (final entry in grouped.entries) {
      final shelf = _shelf(
        AutoCollectionKind.person,
        'person:${entry.key}',
        '${entry.key} 作品',
        '${entry.value.length} 部在库',
        entry.value,
      );
      if (shelf != null) shelves.add(shelf);
    }
    return shelves;
  }
}
