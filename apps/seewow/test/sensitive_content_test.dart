import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/sensitive_content.dart';

void main() {
  test('only literal local loopback endpoints are permitted', () {
    for (final url in [
      'https://example.com/detect',
      'http://localhost/detect',
      'http://192.168.1.1/detect',
      'http://127.0.0.1@evil.test',
      'http://127.0.0.1/?key=secret',
    ]) {
      expect(
        () => SensitiveContentClient.validateEndpoint(url),
        throwsFormatException,
      );
    }
    expect(
      SensitiveContentClient.validateEndpoint('http://127.0.0.1:8888/detect')
          .port,
      8888,
    );
    expect(
      SensitiveContentClient.validateEndpoint('http://[::1]:8888/detect').port,
      8888,
    );
  });
  test('local classifier accepts only confident positive results and bounded protocol', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = 'http://127.0.0.1:${server.port}/classify';
    var reply = <String, dynamic>{'nsfw': true, 'confidence': .95};
    var requests = 0;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body.keys, ['image_base64']);
      expect(base64Decode(body['image_base64']), [1, 2, 3]);
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply));
      await request.response.close();
    });
    final client = SensitiveContentClient(endpoint);
    try {
      expect(await client.detect(Uint8List.fromList([1, 2, 3])), isTrue);
      reply = {'nsfw': false, 'confidence': .99};
      expect(await client.detect(Uint8List.fromList([1, 2, 3])), isFalse);
      reply = {'nsfw': true, 'confidence': .79};
      expect(await client.detect(Uint8List.fromList([1, 2, 3])), isFalse);
      reply = {'nsfw': true};
      await expectLater(
        client.detect(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(requests, 4);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
  test('redirects cannot forward a frame to another server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 302;
      request.response.headers.set('location', 'https://example.com/collect');
      await request.response.close();
    });
    final client = SensitiveContentClient('http://127.0.0.1:${server.port}/');
    try {
      await expectLater(
        client.detect(Uint8List.fromList([1])),
        throwsFormatException,
      );
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
