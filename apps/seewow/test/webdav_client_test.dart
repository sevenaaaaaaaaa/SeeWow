import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/smb_mounter.dart';
import 'package:seewow/sources/webdav_client.dart';

const _multistatus = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop>
      <D:displayname>dav</D:displayname>
      <D:resourcetype><D:collection/></D:resourcetype>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Dune%20Part%20Two/</D:href>
    <D:propstat><D:prop>
      <D:displayname>Dune Part Two</D:displayname>
      <D:resourcetype><D:collection/></D:resourcetype>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Dune%20Part%20Two/Dune%20Part%20Two%20(2024)%202160p.mp4</D:href>
    <D:propstat><D:prop>
      <D:displayname>Dune Part Two (2024) 2160p.mp4</D:displayname>
      <D:resourcetype/>
      <D:getcontentlength>1048576</D:getcontentlength>
      <D:getlastmodified>Wed, 04 Nov 2026 10:00:00 GMT</D:getlastmodified>
    </D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:' + server.port.toString() + '/dav/');
    server.listen((req) async {
      if (req.headers.value('authorization') == null) {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      if (req.method == 'PROPFIND') {
        req.response.statusCode = 207;
        req.response.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
        req.response.write(_multistatus);
        await req.response.close();
        return;
      }
      req.response.statusCode = 200;
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('parses PROPFIND multistatus into entries', () async {
    final client = WebDavClient(base, username: 'swd', password: 'swd');
    final entries = await client.list(base);
    expect(entries.length, 2);
    final dir = entries.firstWhere((e) => e.isDir);
    expect(dir.name, 'Dune Part Two');
    final file = entries.firstWhere((e) => !e.isDir);
    expect(file.name, contains('2160p.mp4'));
    expect(file.isVideo, isTrue);
    expect(file.size, 1048576);
    expect(file.modified, isNotNull);
    expect(file.url.toString(), contains('Dune%20Part%20Two'));
    client.close();
  });

  test('surfaces a friendly error on 401', () async {
    final client = WebDavClient(base);
    await expectLater(client.list(base), throwsA(isA<WebDavException>()));
    client.close();
  });

  test('sends basic auth and a product user agent', () async {
    final client = WebDavClient(base, username: 'swd', password: 'swd');
    final entries = await client.list(base);
    expect(entries, isNotEmpty);
    final expected = 'Basic ' + base64Encode(utf8.encode('swd:swd'));
    expect(client.authHeaders['Authorization'], expected);
    expect(client.authHeaders['User-Agent'], contains('SeeWow'));
    client.close();
  });

  test('parses smb locations with or without scheme', () {
    final a = SmbMounter.parseSmbLocation('smb://192.168.1.10/media/Movies');
    expect(a.host, '192.168.1.10');
    expect(a.share, 'media');
    expect(a.subpath, 'Movies');
    final b = SmbMounter.parseSmbLocation('nas.local/share');
    expect(b.host, 'nas.local');
    expect(b.share, 'share');
    expect(b.subpath, '');
    expect(() => SmbMounter.parseSmbLocation('smb://host'), throwsA(isA<Exception>()));
  });
}
