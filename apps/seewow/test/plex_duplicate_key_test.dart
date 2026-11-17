import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/sources/plex_scanner.dart';

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
              {'key': '1', 'title': '电影', 'type': 'movie', 'count': 2},
            ],
          },
        }),
      );
    } else if (path == '/library/sections/1/all') {
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'totalSize': 2,
            'Metadata': [
              {
                'ratingKey': '101',
                'type': 'movie',
                'title': '甲',
                'Media': [
                  {
                    'width': 1920,
                    'Part': [
                      {'key': '/library/parts/101/a.mkv', 'size': 1},
                    ],
                  },
                ],
              },
              {
                'ratingKey': '101',
                'type': 'movie',
                'title': '乙',
                'Media': [
                  {
                    'width': 1920,
                    'Part': [
                      {'key': '/library/parts/102/b.mkv', 'size': 1},
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

void main() {
  test('RM-05 重复 ratingKey 只跳过重复项，不再让整库扫描失败', () async {
    final server = await _server();
    addTearDown(() => server.close(force: true));
    final scanner = PlexScanner();
    final items = await scanner.scan(
      MediaSource(
        id: 'p1',
        kind: SourceKind.plex,
        name: 'Plex',
        location: 'http://127.0.0.1:${server.port}',
      ),
      'token',
    );
    expect(items.length, 1);
    expect(items.single.title, '甲');
    expect(scanner.lastSkipped, 1);
  });
}