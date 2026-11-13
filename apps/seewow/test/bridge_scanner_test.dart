import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/sources/bridge_scanner.dart';

void main() {
  test('bridge scanner maps the desktop library into playable items', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path != '/bridge/library') {
        request.response.statusCode = 404;
      } else if (request.headers.value('X-SeeWow-Token') != 'token') {
        request.response.statusCode = 401;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'items': [
          {
            'id': 'smb:1',
            'title': 'Bridge Movie',
            'showTitle': null,
            'season': null,
            'episode': null,
            'year': 2024,
            'kind': 'movie',
            'duration': 5400,
            'fileSize': 1024,
            'quality': '1080p',
            'stream': 'http://127.0.0.1:${server.port}/bridge/stream?id=smb:1&key=k',
            'poster': 'http://127.0.0.1:${server.port}/bridge/poster?id=smb:1&key=k',
          },
        ]}));
      }
      await request.response.close();
    });
    try {
      final source = MediaSource(
        id: 'bridge-1',
        kind: SourceKind.bridge,
        name: '电脑媒体库',
        location: 'http://127.0.0.1:${server.port}',
      );
      final items = await BridgeScanner(source, 'token').scan();
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.id, 'bridge-1:smb:1');
      expect(item.title, 'Bridge Movie');
      expect(item.duration, 5400);
      expect(item.locator, contains('/bridge/stream'));
      expect(item.posterUrl, contains('/bridge/poster'));
      expect(item.httpHeaders, isEmpty);
    } finally {
      await server.close(force: true);
    }
  });
}
