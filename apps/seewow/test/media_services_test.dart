import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/tmdb_client.dart';
import 'package:seewow/sources/media_server_scanner.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  final requests = <HttpRequest>[];
  var status = 200;
  var earlyEmpty = false;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-services-');
    requests.clear();
    status = 200;
    earlyEmpty = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      final detail = {
        'id': 42,
        'title': '星际旅程',
        'name': '星际剧集',
        'release_date': '2024-01-01',
        'first_air_date': '2023-04-01',
        'overview': '中文简介',
        'genres': [
          {'name': '科幻'},
        ],
        'vote_count': 20,
        'vote_average': 8.5,
        'runtime': 123,
        'poster_path': '/poster.jpg',
        'backdrop_path': '/backdrop.jpg',
      };
      if (path.contains('/search/')) {
        request.response.write(
          jsonEncode({
            'results': [detail],
          }),
        );
      } else if (path.endsWith('/movie/42') || path.endsWith('/tv/42')) {
        request.response.write(jsonEncode(detail));
      } else {
        final offset = int.parse(
          request.uri.queryParameters['StartIndex'] ?? '0',
        );
        request.response.write(
          jsonEncode({
            'Items': offset == 0
                ? [
                    {
                      'Id': 'movie',
                      'Type': 'Movie',
                      'Name': 'Server Movie',
                      'ProductionYear': 2024,
                      'Overview': '服务端简介',
                      'Genres': ['科幻'],
                      'ImageTags': {'Primary': 'p'},
                      'BackdropImageTags': ['b'],
                      'RunTimeTicks': 600000000,
                      'MediaStreams': [
                        {'Type': 'Video', 'Width': 3840},
                      ],
                      'UserData': {
                        'PlaybackPositionTicks': 100000000,
                        'IsFavorite': true,
                      },
                    },
                  ]
                : earlyEmpty
                ? []
                : [
                    {
                      'Id': 'ep',
                      'Type': 'Episode',
                      'Name': '第一集',
                      'SeriesName': 'Show',
                      'SeriesId': 'show',
                      'ParentIndexNumber': 1,
                      'IndexNumber': 2,
                      'RunTimeTicks': 1200000000,
                      'UserData': {'Played': true},
                    },
                  ],
            'TotalRecordCount': 2,
          }),
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  Uri base(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
  MediaSource source(SourceKind kind) => MediaSource(
    id: 'server',
    kind: kind,
    name: 'Cinema',
    location: base('/emby').toString(),
  );
  test('TMDB search and reviewed details use Chinese, Bearer auth and official image URLs', () async {
    final client = TmdbClient('private-token', base: base('/3'));
    addTearDown(client.close);
    final candidates = await client.search('Original Movie');
    expect(candidates.single.title, '星际旅程');
    final match = await client.details(candidates.single);
    expect(match.genres, ['科幻']);
    expect(match.duration, 7380);
    expect(match.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
    expect(requests.first.uri.queryParameters['language'], 'zh-CN');
    expect(requests.first.uri.queryParameters['query'], 'Original Movie');
    expect(
      requests.every(
        (r) => r.headers.value('Authorization') == 'Bearer private-token',
      ),
      isTrue,
    );
    expect(
      requests.every((r) => !r.uri.toString().contains('private-token')),
      isTrue,
    );
  });
  test(
    'TMDB series searches use TV and never assign series runtime to episodes',
    () async {
      final client = TmdbClient('t', base: base('/3'));
      addTearDown(client.close);
      final candidates = await client.search('Show', series: true);
      final match = await client.details(candidates.single);
      expect(requests.first.uri.path, '/3/search/tv');
      expect(match.duration, 0);
      expect(match.title, '星际剧集');
    },
  );
  for (final kind in [SourceKind.jellyfin, SourceKind.emby]) {
    test(
      '${kind.name} paginates under subpaths and creates authenticated direct-play media',
      () async {
        final items = await MediaServerScanner().scan(
          source(kind),
          'server-secret',
        );
        expect(items.length, 2);
        expect(requests.map((r) => r.uri.queryParameters['StartIndex']), [
          '0',
          '1',
        ]);
        expect(requests.every((r) => r.uri.path == '/emby/Items'), isTrue);
        expect(
          requests.every(
            (r) => r.headers.value('X-Emby-Token') == 'server-secret',
          ),
          isTrue,
        );
        final movie = items.first, episode = items.last;
        expect(movie.id, 'server:movie');
        expect(movie.quality, '4K');
        expect(movie.position, 10);
        expect(movie.isFavorite, isTrue);
        expect(
          movie.locator,
          contains('/emby/Videos/movie/stream?static=true'),
        );
        expect(movie.locator, isNot(contains('server-secret')));
        expect(movie.posterUrl, contains('/emby/Items/movie/Images/Primary'));
        expect(episode.showTitle, 'Show');
        expect(episode.season, 1);
        expect(episode.episode, 2);
        expect(episode.watched, isTrue);
        expect(
          movie.artworkHeaders(movie.posterUrl)['X-Emby-Token'],
          'server-secret',
        );
        expect(
          movie.artworkHeaders('https://image.tmdb.org/t/p/w500/p.jpg'),
          isEmpty,
        );
      },
    );
  }
  test('server authentication failure and incomplete paging cannot replace an old library', () async {
    final store = LibraryStore(directory: dir)
      ..sources.add(source(SourceKind.jellyfin));
    store.items.add(
      MediaItem(
        id: 'old',
        sourceId: 'server',
        kind: MediaKind.movie,
        title: 'Keep',
        locator: '/keep',
      ),
    );
    store.scanner = (s) => MediaServerScanner().scan(s, 'secret');
    status = 401;
    await store.rescan(store.sources.single);
    expect(store.items.single.id, 'old');
    expect(store.sourceErrors['server'], contains('认证失败'));
    status = 200;
    earlyEmpty = true;
    await store.rescan(store.sources.single);
    expect(store.items.single.id, 'old');
    expect(store.sourceErrors['server'], contains('空页'));
  });
  test('reviewed metadata survives restart and rescan while preserving local playback and artwork', () async {
    final raw = MediaItem(
      id: 'm',
      sourceId: 's',
      kind: MediaKind.movie,
      title: 'Filename',
      locator: '/media.mkv',
      posterUrl: '/poster.jpg',
      duration: 100,
      position: 35,
      isFavorite: true,
    );
    final store = LibraryStore(directory: dir)
      ..items.add(raw)
      ..scanner = (_) async => [raw.copyWith(position: 0)];
    final source = MediaSource(
      id: 's',
      kind: SourceKind.local,
      name: 'Local',
      location: '/media',
    );
    store.sources.add(source);
    const match = MediaMetadata(
      id: 42,
      mediaType: 'movie',
      title: '中文片名',
      year: 2024,
      overview: '简介',
      genres: ['科幻'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/p.jpg',
      duration: 7000,
    );
    await store.createCollection('List', ['m']);
    await store.toggleWatchlist(raw);
    await store.applyMetadata('m', match);
    expect(store.items.single.posterUrl, '/poster.jpg');
    expect(store.items.single.duration, 100);
    await store.rescan(source);
    final loaded = LibraryStore(directory: dir);
    await loaded.load();
    final result = loaded.items.single;
    expect(result.title, '中文片名');
    expect(result.overview, '简介');
    expect(result.metadata!.id, 42);
    expect(result.position, 35);
    expect(result.isFavorite, isTrue);
    expect(result.locator, '/media.mkv');
    expect(loaded.collections.single.itemIds, ['m']);
    expect(loaded.taste.watchlist, {'m'});
    await loaded.applyMetadata('m', match.withArtwork(true));
    expect(loaded.items.single.posterUrl, match.posterUrl);
  });
  test(
    'series matching keeps source grouping and reaches newly scanned episodes',
    () async {
      MediaItem episode(String id, int n) => MediaItem(
        id: id,
        sourceId: 'show-source',
        kind: MediaKind.episode,
        title: 'Episode $n',
        showTitle: 'Original Show',
        season: 1,
        episode: n,
        locator: '/show/$id.mkv',
        duration: 1200,
        position: n == 1 ? 300 : 0,
      );
      final store = LibraryStore(directory: dir)
        ..items.addAll([episode('one', 1), episode('two', 2)]);
      final source = MediaSource(
        id: 'show-source',
        kind: SourceKind.local,
        name: 'Shows',
        location: '/show',
      );
      store.sources.add(source);
      await store.applyMetadata(
        'one',
        const MediaMetadata(
          id: 42,
          mediaType: 'tv',
          title: '中文剧名',
          overview: '整部剧简介',
        ),
      );
      expect(store.items.every((e) => e.metadata?.title == '中文剧名'), isTrue);
      expect(store.series.length, 1);
      store.scanner = (_) async => [
        episode('one', 1),
        episode('two', 2),
        episode('three', 3),
      ];
      await store.rescan(source);
      expect(store.items.every((e) => e.metadata?.title == '中文剧名'), isTrue);
      expect(store.items.first.position, 300);
      expect(store.items.last.displayTitle, '中文剧名  S01E03');
      expect(store.series.length, 1);
    },
  );
  test('authentication headers are not persisted and can be restored from a source credential provider', () async {
    final store = LibraryStore(directory: dir)
      ..sources.add(source(SourceKind.jellyfin));
    store.items.add(
      MediaItem(
        id: 'm',
        sourceId: 'server',
        kind: MediaKind.movie,
        title: 'Private',
        locator: base('/video').toString(),
        httpHeaders: {
          'Authorization': 'secret',
          'X-Emby-Token': 'secret',
          'Cookie': 'private',
          'User-Agent': 'SeeWow',
        },
      ),
    );
    await store.save();
    expect(
      await File('${dir.path}/library.json').readAsString(),
      isNot(contains('secret')),
    );
    final loaded = LibraryStore(directory: dir);
    await loaded.load();
    expect(loaded.items.single.httpHeaders, {'User-Agent': 'SeeWow'});
    await loaded.hydrateCredentials((_) async => {'X-Emby-Token': 'restored'});
    expect(loaded.items.single.httpHeaders['X-Emby-Token'], 'restored');
    expect(loaded.items.single.artworkHeaders('/local/poster.jpg'), isEmpty);
  });
  test(
    'invalid external artwork paths and metadata type mismatches are rejected',
    () async {
      expect(TmdbClient.imageUrl('https://other.test/image'), isNull);
      final store = LibraryStore(directory: dir)
        ..items.add(
          MediaItem(
            id: 'e',
            sourceId: 's',
            kind: MediaKind.episode,
            title: 'Episode',
            locator: '/e',
          ),
        );
      await expectLater(
        store.applyMetadata(
          'e',
          const MediaMetadata(id: 1, mediaType: 'movie', title: 'Wrong'),
        ),
        throwsFormatException,
      );
    },
  );
}
