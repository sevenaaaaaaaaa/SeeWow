import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/source_catalog.dart';
import 'package:seewow/sources/source_scanner.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  final requests =
      <
        ({
          String path,
          Map<String, dynamic> body,
          Map<String, String> query,
          String? authorization,
        })
      >[];
  String? proxyUrl;
  var gatewayFailure = false, linkVersion = 0, plexOffsetFailure = false;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-providers-');
    proxyUrl = null;
    requests.clear();
    gatewayFailure = false;
    linkVersion = 0;
    plexOffsetFailure = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final text = await utf8.decoder.bind(req).join();
      final Map<String, dynamic> body = text.isEmpty
          ? {}
          : req.headers.contentType?.mimeType == 'application/json'
          ? jsonDecode(text) as Map<String, dynamic>
          : Map<String, dynamic>.from(Uri.splitQueryString(text));
      requests.add((
        path: req.uri.path,
        body: body,
        query: req.uri.queryParameters,
        authorization: req.headers.value('Authorization'),
      ));
      Map<String, dynamic> response = {};
      switch (req.uri.path) {
        case '/gateway/api/fs/list':
          response = {
            'code': gatewayFailure ? 403 : 200,
            'data': {
              'content': body['path'] == '/夸克/电影'
                  ? [
                      {'name': '科幻', 'is_dir': true},
                    ]
                  : [
                      {
                        'name': 'Space.Movie.2024.2160p.mkv',
                        'is_dir': false,
                        'size': 1000,
                      },
                    ],
              'total': 1,
            },
          };
        case '/gateway/api/fs/get':
          response = {
            'code': 200,
            'data': {
              'raw_url':
                  proxyUrl ??
                  'https://cdn.example.test/stream.mkv?expires=${++linkVersion}',
              'headers': {'User-Agent': 'driver-ua'},
            },
          };
        case '/gateway/proxy':
          req.response.statusCode = 302;
          req.response.headers.set(
            HttpHeaders.locationHeader,
            proxyUrl!.replaceFirst('/gateway/proxy', '/download-target'),
          );
        case '/plex/library/sections':
          response = {
            'MediaContainer': {
              'Directory': [
                {'key': '1', 'type': 'movie'},
                {'key': '2', 'type': 'show'},
              ],
            },
          };
        case '/plex/library/sections/1/all':
        case '/plex/library/sections/2/all':
          final episode = req.uri.queryParameters['type'] == '4';
          response = {
            'MediaContainer': {
              'totalSize': plexOffsetFailure ? 3 : 1,
              'Metadata':
                  plexOffsetFailure &&
                      req.uri.queryParameters['X-Plex-Container-Start'] != '0'
                  ? []
                  : [
                      {
                        'ratingKey': episode ? 'e1' : 'm1',
                        'type': episode ? 'episode' : 'movie',
                        'title': episode ? 'Pilot' : 'Plex Movie',
                        'grandparentTitle': 'Series',
                        'parentIndex': 1,
                        'index': 2,
                        'year': 2024,
                        'duration': 900000,
                        'viewOffset': 30000,
                        'thumb': '/library/metadata/m1/thumb',
                        'Media': [
                          {
                            'width': 3840,
                            'container': 'mkv',
                            'Part': [
                              {
                                'key': '/library/parts/m1/file.mkv',
                                'size': 123,
                              },
                            ],
                          },
                        ],
                      },
                    ],
            },
          };
        case '/dsm/webapi/auth.cgi':
          response = {
            'success': true,
            'data': body['method'] == 'login' ? {'sid': 'private-session'} : {},
          };
        case '/dsm/webapi/entry.cgi':
          response = {
            'success': true,
            'data': {
              'total': 1,
              'files': [
                {
                  'path': '/video/电影.2024.mkv',
                  'name': '电影.2024.mkv',
                  'isdir': false,
                  'additional': {'size': 1234},
                },
              ],
            },
          };
        case '/music/rest/search3.view':
          final q = req.uri.queryParameters;
          expect(
            q['t'],
            md5.convert(utf8.encode('music-password${q['s']}')).toString(),
          );
          expect(q.containsKey('p'), isFalse);
          response = {
            'subsonic-response': {
              'status': 'ok',
              'searchResult3': {
                'song': [
                  {
                    'id': 's1',
                    'title': '中文曲目',
                    'artist': '歌手',
                    'album': '专辑',
                    'duration': 180,
                    'suffix': 'flac',
                    'bitRate': 900,
                  },
                ],
              },
            },
          };
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(response));
      await req.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  String url(String path) => 'http://127.0.0.1:${server.port}$path';
  SourceScanner scanner(String secret) =>
      SourceScanner(readSecret: (_) async => secret);
  test('all requested services have honest, actionable connection modes', () {
    for (final id in [
      'fnos',
      'synology',
      'plex',
      'webdav',
      'jellyfin',
      'quark',
      'baidu',
      'uc',
      'onedrive',
      'googleDrive',
      'mega',
      'pan123',
      'pan115',
      'navidrome',
    ]) {
      expect(providerById(id), isNotNull);
      expect(providerById(id)!.modes, isNotEmpty);
    }
    for (final p in sourceProviders.where((p) => p.category == '网盘')) {
      expect(p.nativePending, isTrue);
      expect(p.modes.first, SourceKind.openlist);
    }
  });
  test('OpenList recursively scans a Chinese mount without persisting direct links', () async {
    final source = MediaSource(
      id: 'q',
      kind: SourceKind.openlist,
      providerId: 'quark',
      name: 'Quark',
      location: url('/gateway'),
      rootPath: '/夸克/电影',
    );
    final items = await scanner('gateway-token').scan(source);
    expect(items.single.title, 'Space Movie');
    expect(items.single.sourceRef, '/夸克/电影/科幻/Space.Movie.2024.2160p.mkv');
    expect(
      requests
          .where((r) => r.path.endsWith('/list'))
          .map((r) => r.body['path']),
      ['/夸克/电影', '/夸克/电影/科幻'],
    );
    expect(requests.every((r) => r.authorization == 'gateway-token'), isTrue);
    final first = await scanner('gateway-token').prepare(items.single, source);
    final second = await scanner('gateway-token').prepare(items.single, source);
    expect(first.locator, contains('expires=1'));
    expect(second.locator, contains('expires=2'));
    expect(first.httpHeaders.containsKey('Authorization'), isFalse);
    expect(first.httpHeaders['User-Agent'], 'driver-ua');
    final stored = jsonEncode(first.toJson());
    expect(stored, isNot(contains('expires=')));
    expect(stored, isNot(contains('gateway-token')));
  });
  test(
    'gateway authorization is removed before cross-origin playback redirects',
    () async {
      final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => cdn.close(force: true));
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      var cdnRead = false;
      cdn.listen((req) async {
        cdnRead = true;
        expect(req.headers.value('Authorization'), isNull);
        req.response.statusCode = 206;
        req.response.write('x');
        await req.response.close();
      });
      proxy.listen((req) async {
        if (req.uri.path.endsWith('/api/fs/get')) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'code': 200,
              'data': {'raw_url': 'http://127.0.0.1:${proxy.port}/proxy'},
            }),
          );
        } else {
          expect(req.headers.value('Authorization'), 'gateway-token');
          req.response.statusCode = 302;
          req.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${cdn.port}/stream',
          );
        }
        await req.response.close();
      });
      final source = MediaSource(
        id: 'q',
        kind: SourceKind.openlist,
        name: 'Gateway',
        location: 'http://127.0.0.1:${proxy.port}',
      );
      final item = MediaItem(
        id: 'm',
        sourceId: 'q',
        kind: MediaKind.movie,
        title: 'Movie',
        locator: 'seewow://source',
        sourceRef: '/movie.mkv',
      );
      final target = await scanner('gateway-token').prepare(item, source);
      expect(cdnRead, isTrue);
      expect(target.httpHeaders.containsKey('Authorization'), isFalse);
      expect(target.locator, 'http://127.0.0.1:${cdn.port}/stream');
    },
  );
  test('gateway driver failure preserves the previous library', () async {
    final source = MediaSource(
      id: 'q',
      kind: SourceKind.openlist,
      name: 'Quark',
      location: url('/gateway'),
      rootPath: '/夸克/电影',
    );
    final store = LibraryStore(directory: dir)
      ..sources.add(source)
      ..scanner = scanner('token').scan;
    await store.rescan(source);
    final oldId = store.items.single.id;
    gatewayFailure = true;
    await store.rescan(source);
    expect(store.items.single.id, oldId);
    expect(store.sourceErrors['q'], contains('403'));
  });
  test('Plex imports movie and episode pages and keeps its token out of URLs and disk', () async {
    final source = MediaSource(
      id: 'p',
      kind: SourceKind.plex,
      name: 'Plex',
      location: url('/plex'),
    );
    final items = await scanner('plex-token').scan(source);
    expect(items.length, 2);
    expect(items.last.kind, MediaKind.episode);
    expect(items.last.displayTitle, 'Series  S01E02');
    expect(items.first.quality, '4K');
    expect(items.first.locator, url('/plex/library/parts/m1/file.mkv'));
    expect(items.first.httpHeaders['X-Plex-Token'], 'plex-token');
    expect(
      jsonEncode(items.map((i) => i.toJson()).toList()),
      isNot(contains('plex-token')),
    );
    expect(
      (await scanner('restored').headersFor(source))['X-Plex-Token'],
      'restored',
    );
  });
  test('Plex partial pages fail instead of replacing an old library', () async {
    plexOffsetFailure = true;
    final source = MediaSource(
      id: 'p',
      kind: SourceKind.plex,
      name: 'Plex',
      location: url('/plex'),
    );
    await expectLater(scanner('t').scan(source), throwsFormatException);
  });
  test('Synology uses form login, read-only file operations and fresh playback sessions', () async {
    final source = MediaSource(
      id: 's',
      kind: SourceKind.synology,
      providerId: 'synology',
      name: 'DSM',
      location: url('/dsm'),
      username: 'user',
      rootPath: '/video',
    );
    final items = await scanner('password+&中文').scan(source);
    expect(items.single.sourceRef, '/video/电影.2024.mkv');
    expect(requests.first.body['passwd'], 'password+&中文');
    expect(requests.first.query, isEmpty);
    expect(requests.any((r) => r.body['method'] == 'logout'), isTrue);
    final target = await scanner('password+&中文').prepare(items.single, source);
    expect(
      Uri.parse(target.locator).queryParameters['_sid'],
      'private-session',
    );
    expect(jsonEncode(target.toJson()), isNot(contains('private-session')));
    expect(
      requests.every(
        (r) => ![
          'delete',
          'rename',
          'create',
          'upload',
        ].contains(r.body['method']),
      ),
      isTrue,
    );
  });
  test('Navidrome imports music and resolves salted authentication only for playback', () async {
    final source = MediaSource(
      id: 'n',
      kind: SourceKind.navidrome,
      name: 'Music',
      location: url('/music'),
      username: 'listener',
    );
    final items = await scanner('music-password').scan(source);
    expect(items.single.kind, MediaKind.audio);
    expect(items.single.artist, '歌手');
    expect(items.single.album, '专辑');
    final target = await scanner('music-password')
        .prepare(items.single, source);
    final q = Uri.parse(target.locator).queryParameters;
    expect(
      q['t'],
      md5.convert(utf8.encode('music-password${q['s']}')).toString(),
    );
    expect(q['id'], 's1');
    expect(q.containsKey('p'), isFalse);
    expect(jsonEncode(target.toJson()), isNot(contains(q['t']!)));
    final store = LibraryStore(directory: dir)..items.add(items.single);
    expect(store.recommendations(), isEmpty);
  });
  test('editing a source preserves identity, collections, metadata and playback across endpoint changes', () async {
    final source = MediaSource(
      id: 's',
      kind: SourceKind.plex,
      name: 'Old',
      location: url('/old'),
      providerId: 'plex',
    );
    final store = LibraryStore(directory: dir)..sources.add(source);
    store.items.add(
      MediaItem(
        id: 'stable',
        sourceId: 's',
        kind: MediaKind.movie,
        title: 'Film',
        locator: '${source.location}/movie',
        duration: 100,
        position: 40,
        isFavorite: true,
      ),
    );
    await store.createCollection('Saved', ['stable']);
    store.scanner = (s) async => [
      MediaItem(
        id: 'stable',
        sourceId: 's',
        kind: MediaKind.movie,
        title: 'Film',
        locator: '${s.location}/movie',
      ),
    ];
    await store.updateSource(
      MediaSource(
        id: 's',
        kind: SourceKind.plex,
        name: 'New',
        location: url('/new'),
        providerId: 'plex',
        rootPath: '/scope',
      ),
    );
    expect(store.items.single.position, 40);
    expect(store.items.single.isFavorite, isTrue);
    expect(store.collections.single.itemIds, ['stable']);
    expect(store.sources.single.providerId, 'plex');
    expect(store.sources.single.rootPath, '/scope');
    final reload = LibraryStore(directory: dir);
    await reload.load();
    expect(reload.sources.single.rootPath, '/scope');
  });
}
