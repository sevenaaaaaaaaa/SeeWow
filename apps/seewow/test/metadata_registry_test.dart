import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/metadata_registry.dart';
import 'package:seewow/metadata/metadata_source.dart';

/// A catalogue that answers from memory, so the chain can be tested without
/// the network.
class _FakeSource implements MetadataSource {
  _FakeSource({
    required this.id,
    this.seriesOnlyValue = false,
    this.results = const [],
    this.detailsResult,
    this.error,
  });

  @override
  final String id;

  @override
  String get label => '假数据源 $id';

  @override
  bool get seriesOnly => seriesOnlyValue;
  final bool seriesOnlyValue;

  final List<MediaMetadata> results;
  final MediaMetadata? detailsResult;
  final Object? error;
  int searches = 0, detailCalls = 0;
  bool closed = false;

  @override
  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  }) async {
    searches++;
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async {
    detailCalls++;
    return detailsResult ?? candidate;
  }

  @override
  void close() => closed = true;
}

MediaMetadata _item(
  String provider,
  int id, {
  String title = '银翼杀手',
  String overview = '',
  int? year = 1982,
  double? rating,
}) => MediaMetadata(
  id: id,
  mediaType: 'movie',
  title: title,
  overview: overview,
  year: year,
  rating: rating,
  provider: provider,
);

void main() {
  group('annotateFields', () {
    test('only records fields that actually carry a value', () {
      final tagged = annotateFields(
        _item('tvmaze', 7, overview: '简介', rating: 8.5),
        'TVmaze',
      );
      expect(tagged.fieldSources[MetadataFields.title], 'TVmaze');
      expect(tagged.fieldSources[MetadataFields.overview], 'TVmaze');
      expect(tagged.fieldSources[MetadataFields.rating], 'TVmaze');
      expect(tagged.fieldSources.containsKey(MetadataFields.poster), isFalse);
      expect(tagged.fieldSources.containsKey(MetadataFields.duration), isFalse);
    });
  });

  group('mergeMetadata', () {
    test('fills gaps from the fallback and keeps both provenances', () {
      final primary = annotateFields(
        _item('tmdb', 1, title: '银翼杀手'),
        'TMDB',
      );
      final fallback = _item(
        'bangumi',
        2,
        overview: '洛杉矶的雨夜。',
        rating: 8.9,
      );
      final merged = mergeMetadata(primary, fallback);
      expect(merged.title, '银翼杀手');
      expect(merged.overview, '洛杉矶的雨夜。');
      expect(merged.rating, 8.9);
      expect(merged.fieldSources[MetadataFields.title], 'TMDB');
      expect(merged.fieldSources[MetadataFields.overview], 'Bangumi');
      expect(merged.fieldSources[MetadataFields.rating], 'Bangumi');
    });

    test('never overwrites a field the primary already answered', () {
      final primary = _item('tmdb', 1, overview: '主源简介', rating: 8.1);
      final fallback = _item('tvmaze', 2, overview: '备用简介', rating: 9.9);
      final merged = mergeMetadata(primary, fallback);
      expect(merged.overview, '主源简介');
      expect(merged.rating, 8.1);
      expect(merged.fieldSources[MetadataFields.overview], 'TMDB');
    });
  });

  group('MetadataRegistry.search', () {
    test('falls back when the first catalogue fails', () async {
      final broken = _FakeSource(id: 'tmdb', error: const FormatException('额度用完'));
      final working = _FakeSource(id: 'tvmaze', results: [_item('tvmaze', 9)]);
      final registry = MetadataRegistry([broken, working]);
      final outcome = await registry.search('银翼杀手', series: false);
      expect(outcome.results.length, 1);
      expect(outcome.answeredBy, 'tvmaze');
      expect(outcome.attempts.first.error, '额度用完');
      expect(outcome.attempts.last.count, 1);
      expect(outcome.results.single.fieldSources[MetadataFields.title], 'TVmaze');
      expect(outcome.summary, contains('失败'));
    });

    test('skips a series-only catalogue for films', () async {
      final seriesOnly = _FakeSource(id: 'tvmaze', seriesOnlyValue: true);
      final movies = _FakeSource(id: 'bangumi', results: [_item('bangumi', 3)]);
      final registry = MetadataRegistry([seriesOnly, movies]);
      final outcome = await registry.search('银翼杀手', series: false);
      expect(seriesOnly.searches, 0);
      expect(outcome.results, isNotEmpty);
    });

    test('stops once the minimum is reached', () async {
      final first = _FakeSource(id: 'tmdb', results: [
        _item('tmdb', 1, title: 'A'),
        _item('tmdb', 2, title: 'B'),
      ]);
      final second = _FakeSource(id: 'bangumi', results: [_item('bangumi', 3)]);
      final registry = MetadataRegistry([first, second]);
      final outcome = await registry.search('x', series: false, minimum: 2);
      expect(outcome.results.length, 2);
      expect(second.searches, 0);
    });

    test('deduplicates the same work answered twice', () async {
      final duplicate = _item('tmdb', 5);
      final registry = MetadataRegistry([
        _FakeSource(id: 'tmdb', results: [duplicate, duplicate]),
      ]);
      final outcome = await registry.search('x', series: false, minimum: 5);
      expect(outcome.results.length, 1);
    });

    test('reports the preferred catalogue first without hiding the rest', () async {
      final tmdb = _FakeSource(id: 'tmdb', results: [_item('tmdb', 1)]);
      final bangumi = _FakeSource(id: 'bangumi', results: [_item('bangumi', 2)]);
      final registry = MetadataRegistry([tmdb, bangumi]);
      final outcome = await registry.search(
        'x',
        series: false,
        preferred: 'bangumi',
        minimum: 5,
      );
      expect(outcome.attempts.first.sourceId, 'bangumi');
      expect(outcome.results.length, 2);
    });

    test('throws only when every catalogue failed', () async {
      final registry = MetadataRegistry([
        _FakeSource(id: 'tmdb', error: const FormatException('断网')),
      ]);
      expect(
        () => registry.search('x', series: false),
        throwsA(isA<FormatException>()),
      );
    });

    test('an empty answer is not an error', () async {
      final registry = MetadataRegistry([
        _FakeSource(id: 'tmdb', results: const []),
      ]);
      final outcome = await registry.search('x', series: false);
      expect(outcome.results, isEmpty);
      expect(outcome.attempts.single.ok, isTrue);
    });
  });

  group('MetadataRegistry.details', () {
    test('completes the work from matching candidates of other catalogues', () async {
      final tmdbResult = _item('tmdb', 1, title: '银翼杀手');
      final bangumiResult = _item(
        'bangumi',
        2,
        title: '银翼杀手',
        overview: '动画版简介',
      );
      final tmdb = _FakeSource(
        id: 'tmdb',
        detailsResult: _item('tmdb', 1, title: '银翼杀手', rating: 8.2),
      );
      final registry = MetadataRegistry([tmdb]);
      final full = await registry.details(
        tmdbResult,
        supplements: [bangumiResult],
      );
      expect(full.rating, 8.2);
      expect(full.overview, '动画版简介');
      expect(full.fieldSources[MetadataFields.overview], 'Bangumi');
    });

    test('ignores supplements for a different work', () async {
      final candidate = _item('tmdb', 1);
      final other = _item('bangumi', 2, title: '完全不同的片子', overview: '不该出现');
      final registry = MetadataRegistry([
        _FakeSource(id: 'tmdb', detailsResult: _item('tmdb', 1)),
      ]);
      final full = await registry.details(candidate, supplements: [other]);
      expect(full.overview, '');
    });

    test('refuses an unknown catalogue instead of guessing', () async {
      final registry = MetadataRegistry(const []);
      expect(
        () => registry.details(_item('nfo', 1)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('close reaches every catalogue', () {
    final first = _FakeSource(id: 'tmdb');
    final second = _FakeSource(id: 'bangumi');
    MetadataRegistry([first, second]).close();
    expect(first.closed, isTrue);
    expect(second.closed, isTrue);
  });
}
