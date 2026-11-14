import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/sources/plex_scanner.dart';

/// A real HTTP server, because [PlexScanner] talks the real Plex protocol.
/// Mocking the transport would let a broken request path pass unnoticed.
Future<HttpServer> _server() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/library/sections') {
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'Directory': [
              {'key': '1', 'title': '电影', 'type': 'movie', 'count': 1},
              {'key': '2', 'title': '剧集', 'type': 'show', 'count': 1},
              {'key': '3', 'title': '照片', 'type': 'photo', 'count': 9},
            ],
          },
        }),
      );
    } else if (path == '/library/sections/1/all') {
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'totalSize': 1,
            'Metadata': [
              {
                'ratingKey': '101',
                'type': 'movie',
                'title': '海边的电影',
                'year': 2021,
                'addedAt': 1700000000,
                'Media': [
                  {
                    'width': 3840,
                    'container': 'mkv',
                    'Part': [
                      {'key': '/library/parts/101/file.mkv', 'size': 2048},
                    ],
                  },
                ],
              },
            ],
          },
        }),
      );
    } else if (path == '/library/sections/2/all') {
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'totalSize': 1,
            'Metadata': [
              {
                'ratingKey': '201',
                'type': 'episode',
                'title': '第一集',
                'grandparentTitle': '长夜',
                'Media': [
                  {
                    'width': 1920,
                    'container': 'mp4',
                    'Part': [
                      {'key': '/library/parts/201/e1.mp4', 'size': 1024},
                    ],
                  },
                ],
              },
            ],
          },
        }),
      );
    } else {
      request.response.statusCode = 404;
      request.response.write('{}');
    }
    await request.response.close();
  });
  return server;
}

MediaSource _source(String uri, {List<String> folders = const []}) =>
    MediaSource(
      id: 'plex-1',
      kind: SourceKind.plex,
      name: '测试 Plex',
      location: uri,
      folders: folders,
    );

void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await _server();
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sections list only video libraries', () async {
    final sections = await PlexScanner().sections(_source(base), 'token');
    expect(sections.map((s) => s.key), ['1', '2']);
    expect(sections.map((s) => s.type), ['movie', 'show']);
    expect(sections.first.title, '电影');
    expect(sections.first.count, 1);
  });

  test('an empty selection imports every video library', () async {
    final items = await PlexScanner().scan(_source(base), 'token');
    expect(items.map((i) => i.title), containsAll(['海边的电影', '第一集']));
    expect(items.length, 2);
  });

  test('a folder selection narrows the scan to those libraries', () async {
    final items = await PlexScanner().scan(
      _source(base, folders: ['1']),
      'token',
    );
    expect(items.length, 1);
    expect(items.single.title, '海边的电影');
    expect(items.single.quality, '4K');
  });

  test('an explicit sectionKeys argument wins over the stored folders', () async {
    final items = await PlexScanner().scan(
      _source(base, folders: ['1']),
      'token',
      sectionKeys: {'2'},
    );
    expect(items.single.showTitle, '长夜');
  });

  test('folders survive the library round trip', () {
    final restored = MediaSource.fromJson(
      jsonDecode(
            jsonEncode(_source(base, folders: ['1', '2']).toJson()),
          )
          as Map<String, dynamic>,
    );
    expect(restored.folders, ['1', '2']);
    final legacy = MediaSource.fromJson({
      'id': 'old',
      'kind': 'plex',
      'name': '旧连接',
      'location': base,
    });
    expect(legacy.folders, isEmpty);
  });

  test('a rescan keeps the folder selection instead of resetting it', () async {
    // The scanner rebuilds the source row after every scan; forgetting the
    // selection there silently turns a narrowed Plex source back into a full
    // import on the next refresh.
    final dir = await Directory.systemTemp.createTemp('seewow-plex-rescan-');
    try {
      final store = LibraryStore(directory: dir);
      store.scanner = (source) async => const <MediaItem>[];
      final source = _source(base, folders: ['1']);
      store.sources.add(source);
      await store.rescan(source);
      expect(store.sources.single.folders, ['1']);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
