import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/local_stream_proxy.dart';

void main() {
  test('loopback proxy injects headers and forwards range requests', () async {
    var seenAuth = '';
    var seenRange = '';
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      seenAuth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      seenRange = request.headers.value(HttpHeaders.rangeHeader) ?? '';
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set('content-range', 'bytes 0-3/4');
      request.response.headers.set('accept-ranges', 'bytes');
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    try {
      final proxyUrl = await LocalStreamProxy.instance.urlFor(
        Uri.parse('http://127.0.0.1:${upstream.port}/video'),
        const {'Authorization': 'Bearer token'},
      );
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(proxyUrl));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
      final response = await request.close();
      final body = await response.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      expect(response.statusCode, 206);
      expect(body, [1, 2, 3, 4]);
      expect(seenAuth, 'Bearer token');
      expect(seenRange, 'bytes=0-3');
      client.close(force: true);
    } finally {
      LocalStreamProxy.instance.clear();
      await upstream.close(force: true);
    }
  });
}
