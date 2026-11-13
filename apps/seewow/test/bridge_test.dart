import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/remote/remote_hub.dart';
import 'package:seewow/remote/remote_server.dart';

class _Bridge implements RemoteBridgeHost {
  _Bridge(this.item);
  final MediaItem item;
  @override
  List<MediaItem> get bridgeItems => [item];
  @override
  Future<MediaItem?> bridgeItem(String id) async => id == item.id ? item : null;
  @override
  Future<MediaItem> bridgePrepare(MediaItem item) async => item;
}

Future<(int, List<int>, Map<String, String>)> _get(
  String url, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) responseHeaders[name] = values.first;
    });
    return (response.statusCode, bytes, responseHeaders);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('bridge exposes library, range stream and rejects bad keys', () async {
    final root = await Directory.systemTemp.createTemp('seewow-bridge-');
    final file = File('${root.path}/movie.mp4');
    await file.writeAsBytes(List<int>.generate(10, (i) => i + 1));
    final item = MediaItem(
      id: 'smb-1:movie',
      sourceId: 'smb-1',
      kind: MediaKind.movie,
      title: 'Bridge Movie',
      locator: Uri.file(file.path).toString(),
      year: 2024,
      container: 'mp4',
    );
    final server = RemoteServer();
    server.bridgeHost = _Bridge(item);
    final key = 'a' * 32;
    try {
      await server.start(
        code: '123456',
        httpPort: 0,
        udpPort: 0,
        bridgeKey: key,
      );
      final base = 'http://127.0.0.1:${server.httpPort}';
      final pairClient = HttpClient();
      final pairRequest = await pairClient.postUrl(
        Uri.parse('$base/api/pair'),
      );
      pairRequest.headers.contentType = ContentType.json;
      pairRequest.write(jsonEncode({'code': '123456', 'device': 'test'}));
      final pairResponse = await pairRequest.close();
      final pairBody = jsonDecode(await utf8.decodeStream(pairResponse)) as Map;
      final token = pairBody['token'] as String;
      expect(pairBody['bridgeKey'], key);
      pairClient.close(force: true);

      final library = await _get(
        '$base/bridge/library',
        headers: {'X-SeeWow-Token': token},
      );
      expect(library.$1, 200);
      final decoded = jsonDecode(utf8.decode(library.$2)) as Map;
      final items = decoded['items'] as List;
      expect(items, hasLength(1));
      final stream = (items.single as Map)['stream'] as String;
      expect(stream, contains('key=$key'));

      final ranged = await _get(
        stream,
        headers: {'Range': 'bytes=2-5'},
      );
      expect(ranged.$1, 206);
      expect(ranged.$2, [3, 4, 5, 6]);
      expect(ranged.$3['content-range'], 'bytes 2-5/10');

      final denied = await _get('$base/bridge/stream?id=smb-1:movie&key=bad');
      expect(denied.$1, 403);
    } finally {
      await server.stop();
      await root.delete(recursive: true);
    }
  });
}
