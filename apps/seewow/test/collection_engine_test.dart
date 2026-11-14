import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/collection_engine.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';

MediaItem _movie({
  required String title,
  List<String> genres = const [],
  int? year,
  double rating = 0,
  String quality = '',
  double duration = 0,
  bool watched = false,
  double position = 0,
  DateTime? addedAt,
  List<MediaPerson> people = const [],
  List<String> countries = const [],
}) => MediaItem(
  id: title,
  sourceId: 's',
  kind: MediaKind.movie,
  title: title,
  locator: '/media/$title',
  genres: genres,
  year: year,
  rating: rating == 0 ? null : rating,
  quality: quality,
  duration: duration,
  position: position,
  addedAt: addedAt,
  metadata: MediaMetadata(
    id: title.hashCode,
    mediaType: 'movie',
    title: title,
    people: people,
    countries: countries,
  ),
);

MediaItem _episode(String show, int season) => MediaItem(
  id: '$show-s$season',
  sourceId: 's',
  kind: MediaKind.episode,
  title: '$show 第 $season 集',
  showTitle: show,
  season: season,
  episode: 1,
  locator: '/media/$show/$season',
  addedAt: DateTime(2026, 1, season),
);

CollectionEngine _engine({int minItems = 4}) =>
    const CollectionEngine(minItems: 4).copyWith(minItems: minItems);

extension on CollectionEngine {
  CollectionEngine copyWith({int? minItems}) =>
      CollectionEngine(minItems: minItems ?? this.minItems);
}

void main() {
  test('an empty library produces no shelves', () {
    expect(const CollectionEngine().build(const []), isEmpty);
  });

  test('a genre shelf needs the minimum number of entries', () {
    final library = [
      for (var i = 0; i < 4; i++) _movie(title: '科幻$i', genres: ['科幻']),
      for (var i = 0; i < 3; i++) _movie(title: '悬疑$i', genres: ['悬疑']),
    ];
    final shelves = _engine().build(library);
    expect(shelves.any((s) => s.id == 'genre:科幻'), isTrue);
    expect(shelves.any((s) => s.id == 'genre:悬疑'), isFalse);
  });

  test('documentary keeps its dedicated shelf and never doubles here', () {
    final library = [
      for (var i = 0; i < 5; i++) _movie(title: '纪录$i', genres: ['纪录片']),
    ];
    final shelves = _engine().build(library);
    expect(shelves.any((s) => s.id == 'genre:纪录片'), isFalse);
  });

  test('a series is one shelf card, not one card per episode', () {
    final library = [
      for (var s = 1; s <= 3; s++) _episode('长夜', s),
      for (var s = 1; s <= 3; s++) _episode('白昼', s),
      for (var s = 1; s <= 2; s++) _episode('黄昏', s),
      for (var s = 1; s <= 2; s++) _episode('黎明', s),
    ];
    final shelves = _engine().build(library);
    final shows = shelves.firstWhere((s) => s.id == 'shows');
    expect(shows.items.map((i) => i.showTitle).toSet(), {'长夜', '白昼', '黄昏', '黎明'});
    expect(shows.items.length, 4);
  });

  test('decades bucket by ten years', () {
    final library = [
      for (final year in [1990, 1994, 1998, 1995]) _movie(title: '片$year', year: year),
      for (final year in [2010, 2015, 2017, 2019]) _movie(title: '新$year', year: year),
    ];
    final shelves = _engine().build(library);
    expect(shelves.any((s) => s.id == 'decade:1990'), isTrue);
    expect(shelves.any((s) => s.id == 'decade:2010'), isTrue);
    expect(shelves.any((s) => s.id == 'decade:2000'), isFalse);
  });

  test('runtime shelves split at one hour and 100 minutes', () {
    final library = [
      for (var i = 0; i < 4; i++) _movie(title: '短片$i', duration: 1800),
      for (var i = 0; i < 4; i++) _movie(title: '中场$i', duration: 4500),
      for (var i = 0; i < 4; i++) _movie(title: '长片$i', duration: 7200),
    ];
    final shelves = _engine().build(library);
    expect(shelves.any((s) => s.id == 'runtime:short'), isTrue);
    expect(shelves.any((s) => s.id == 'runtime:mid'), isTrue);
    expect(shelves.any((s) => s.id == 'runtime:long'), isTrue);
  });

  test('ratings and quality shelves only take matching entries', () {
    final library = [
      for (var i = 0; i < 4; i++)
        _movie(title: '高分$i', rating: 8.6, quality: '2160p HDR'),
      for (var i = 0; i < 4; i++) _movie(title: '普通$i', rating: 6.0),
    ];
    final shelves = _engine().build(library);
    final top = shelves.firstWhere((s) => s.id == 'rating:top');
    expect(top.items.every((i) => (i.rating ?? 0) >= 8), isTrue);
    final hdr = shelves.firstWhere((s) => s.id == 'quality:hdr');
    expect(hdr.items.length, 4);
  });

  test('closed libraries do not leak into hidden gems', () {
    final old = DateTime.now().subtract(const Duration(days: 90));
    final library = [
      for (var i = 0; i < 4; i++)
        _movie(title: '冷门$i', rating: 8.1, addedAt: old),
    ];
    final shelves = _engine().build(library);
    final gems = shelves.firstWhere((s) => s.id == 'hidden-gems');
    expect(gems.items.length, 4);
  });

  test('shelves interleave by kind instead of stacking one dimension', () {
    final library = [
      for (var i = 0; i < 6; i++) _movie(title: '科幻$i', genres: ['科幻'], rating: 9),
      for (var i = 0; i < 6; i++) _movie(title: '剧情$i', genres: ['剧情'], rating: 8.5),
      for (var i = 0; i < 6; i++) _movie(title: '喜剧$i', genres: ['喜剧'], rating: 8.2),
    ];
    final shelves = _engine().build(library);
    expect(shelves.length, greaterThanOrEqualTo(3));
    final kinds = shelves.map((s) => s.kind).toList();
    expect(kinds.first, isNot(kinds[1]));
  });

  test('a director with three films does not make a shelf, four does', () {
    List<MediaPerson> director(String name) => [
      MediaPerson(name: name, department: 'Directing'),
    ];
    final library = [
      for (var i = 0; i < 4; i++)
        _movie(title: '作品$i', people: director('王家卫')),
      for (var i = 0; i < 3; i++)
        _movie(title: '别作$i', people: director('张三')),
    ];
    final shelves = _engine().build(library);
    expect(shelves.any((s) => s.id == 'person:王家卫'), isTrue);
    expect(shelves.any((s) => s.id == 'person:张三'), isFalse);
  });

  test('a larger dimension outranks a smaller one of the same kind', () {
    final library = [
      for (var i = 0; i < 20; i++) _movie(title: '科幻$i', genres: ['科幻']),
      for (var i = 0; i < 5; i++) _movie(title: '喜剧$i', genres: ['喜剧']),
    ];
    final shelves = _engine().build(library);
    final genres = shelves.where((s) => s.kind == AutoCollectionKind.genre).toList();
    expect(genres.first.id, 'genre:科幻');
    expect(genres.first.total, 20);
    expect(genres.first.items.length, lessThanOrEqualTo(12));
  });

  test('hidden gems are decided by an injectable clock', () {
    final day = DateTime(2026, 3, 1);
    final library = [
      for (var i = 0; i < 4; i++)
        _movie(
          title: '冷门$i',
          rating: 8.1,
          addedAt: day.subtract(const Duration(days: 90)),
        ),
    ];
    final engine = const CollectionEngine();
    expect(
      engine.build(library, now: day).any((s) => s.id == 'hidden-gems'),
      isTrue,
    );
    // Same library, a clock so early that nothing is "old" yet.
    expect(
      engine
          .build(library, now: library.first.addedAt!.add(const Duration(days: 1)))
          .any((s) => s.id == 'hidden-gems'),
      isFalse,
    );
  });

  test('the same library always returns the same shelf order', () {
    final library = [
      for (var i = 0; i < 5; i++)
        _movie(title: '片$i', genres: ['科幻'], rating: 8.5, year: 2010 + i),
      for (var i = 0; i < 5; i++)
        _movie(title: '剧$i', genres: ['剧情'], rating: 7.5, year: 2015 + i),
    ];
    final engine = const CollectionEngine();
    final first = engine.build(library).map((s) => s.id).toList();
    final second = engine.build(library).map((s) => s.id).toList();
    expect(first, second);
  });
}
