import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/library_intelligence.dart';
import 'package:seewow/domain/media_item.dart';

MediaItem film(
  String id, {
  List<String> genres = const ['科幻'],
  double duration = 6000,
  double position = 0,
  double rating = 8,
  String source = 'a',
  String? show,
  int? episode,
}) => MediaItem(
  id: id,
  sourceId: source,
  kind: show == null ? MediaKind.movie : MediaKind.episode,
  title: id,
  showTitle: show,
  season: show == null ? null : 1,
  episode: episode,
  locator: '/media/$id.mkv',
  year: 2024,
  genres: genres,
  duration: duration,
  position: position,
  rating: rating,
);
void main() {
  test(
    'recommendations obey taste, exclusion, time budgets and series diversity',
    () {
      final taste = TasteProfile()
        ..genres.add('科幻')
        ..dislikedIds.add('hidden');
      final items = [
        film('scifi'),
        film('comedy', genres: ['喜剧'], rating: 9),
        film('seen', position: 6000),
        film('hidden'),
        film('long', duration: 12000),
        film('unknown', duration: 0),
        film('ep1', show: 'Show', episode: 1),
        film('ep2', show: 'Show', episode: 2),
      ];
      final engine = RecommendationEngine();
      expect(engine.recommend(items, taste).first.item.id, isNot('comedy'));
      final picks = engine.recommend(items, taste, prompt: '科幻 120 分钟');
      expect(picks.map((p) => p.item.id), isNot(contains('comedy')));
      expect(picks.map((p) => p.item.id), isNot(contains('seen')));
      expect(picks.map((p) => p.item.id), isNot(contains('hidden')));
      expect(picks.map((p) => p.item.id), isNot(contains('long')));
      expect(picks.map((p) => p.item.id), isNot(contains('unknown')));
      expect(picks.where((p) => p.item.showTitle == 'Show').length, 1);
      expect(picks.every((p) => p.reason.isNotEmpty), isTrue);
    },
  );
  test('search composes terms, source, genre and watchlist', () {
    final taste = TasteProfile()..watchlist.add('Alpha');
    final items = [
      film('Alpha'),
      film('Beta'),
      film('Alpha copy', source: 'b'),
    ];
    final result = const LibraryQuery(
      text: 'alpha 2024',
      sourceId: 'a',
      genre: '科幻',
      watch: WatchFilter.watchlist,
    ).apply(items, taste);
    expect(result.map((i) => i.id), ['Alpha']);
  });
  test('audit distinguishes episodes and flags cross-source duplicates', () {
    final audit = LibraryAudit([
      film('same'),
      film('same', source: 'b'),
      film('e1', show: 'show', episode: 1),
      film('e2', show: 'show', episode: 2),
    ]);
    expect(audit.duplicates.length, 1);
    expect(audit.missingMetadata.length, 4);
  });
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-library-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'preferences, collections and progress survive restart with queued writes',
    () async {
      final store = LibraryStore(directory: dir)
        ..items.addAll([film('a'), film('b')]);
      await Future.wait([
        store.toggleGenre('科幻'),
        store.toggleWatchlist(store.items.first),
        store.setFavorite(store.items.first, true),
      ]);
      await store.setDisliked(store.items.last, true);
      await store.updatePosition(store.items.first, 120, 6000);
      await store.createCollection('周末', ['a', 'a', 'unknown']);
      final loaded = LibraryStore(directory: dir);
      await loaded.load();
      expect(loaded.taste.genres, {'科幻'});
      expect(loaded.taste.watchlist, {'a'});
      expect(loaded.taste.dislikedIds, {'b'});
      expect(loaded.items.first.isFavorite, isTrue);
      expect(loaded.items.first.position, 120);
      expect(loaded.taste.lastPlayed.keys, contains('a'));
      expect(loaded.collections.single.itemIds, ['a']);
    },
  );
  test(
    'offline scans preserve all previous items and expose durable failure',
    () async {
      final source = MediaSource(
        id: 'a',
        kind: SourceKind.local,
        name: 'NAS',
        location: '/offline',
      );
      final store = LibraryStore(directory: dir)
        ..sources.add(source)
        ..items.add(film('keep'))
        ..scanner = (_) async => throw const FileSystemException('offline');
      await store.rescan(source);
      expect(store.items.single.id, 'keep');
      expect(store.sourceErrors['a'], contains('offline'));
      expect(store.scanning, isFalse);
      final loaded = LibraryStore(directory: dir);
      await loaded.load();
      expect(loaded.sourceErrors.keys, contains('a'));
      store.scanner = (_) async => [film('keep')];
      await store.rescan(source);
      expect(store.sourceErrors, isEmpty);
      expect(store.sources.single.lastScan, isNotNull);
    },
  );
  test(
    'rescans deduplicate running work and retain playback and favorites',
    () async {
      final source = MediaSource(
        id: 'a',
        kind: SourceKind.local,
        name: 'local',
        location: '/media',
      );
      final old = film('keep').copyWith(position: 450, isFavorite: true);
      final completer = Completer<List<MediaItem>>();
      var calls = 0;
      final store = LibraryStore(directory: dir)
        ..sources.add(source)
        ..items.add(old)
        ..scanner = (_) {
          calls++;
          return completer.future;
        };
      final first = store.rescan(source);
      final second = store.rescan(source);
      expect(calls, 1);
      completer.complete([film('keep')]);
      await Future.wait([first, second]);
      expect(store.items.single.position, 450);
      expect(store.items.single.isFavorite, isTrue);
    },
  );
  test('disconnect during a scan cannot resurrect removed media', () async {
    final source = MediaSource(
      id: 'a',
      kind: SourceKind.local,
      name: 'local',
      location: '/media',
    );
    final completer = Completer<List<MediaItem>>();
    final store = LibraryStore(directory: dir)
      ..sources.add(source)
      ..scanner = (_) => completer.future;
    final scanning = store.rescan(source);
    final removing = store.removeSource(source);
    completer.complete([film('new')]);
    await Future.wait([scanning, removing]);
    expect(store.items, isEmpty);
    expect(store.sources, isEmpty);
  });
  test('legacy library JSON loads without losing items', () async {
    await File('${dir.path}/library.json').writeAsString(
      jsonEncode({
        'items': [film('legacy').toJson()],
        'sources': [],
      }),
    );
    final store = LibraryStore(directory: dir);
    await store.load();
    expect(store.items.single.id, 'legacy');
    expect(store.collections, isEmpty);
    expect(store.taste.genres, isEmpty);
  });
}
