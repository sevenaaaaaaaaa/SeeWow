import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/local_scanner.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/metadata/nfo_reader.dart';
import 'package:seewow/sources/webdav_client.dart';
import 'package:seewow/sources/webdav_scanner.dart';

void main() {
  test('NFO reads Chinese text, CDATA, default ratings and genres', () {
    final info = NfoInfo.parse(
      '<movie><title>中文电影</title><year>2024</year><plot><![CDATA[剧情 <片段>]]></plot><genre>剧情</genre><genre>科幻</genre><runtime>120</runtime><ratings><rating name="tmdb"><value>7.1</value></rating><rating name="douban" default="true"><value>8.8</value></rating></ratings></movie>',
    );
    expect(info.title, '中文电影');
    expect(info.overview, '剧情 <片段>');
    expect(info.rating, 8.8);
    expect(info.genres, ['剧情', '科幻']);
    expect(info.duration, 7200);
  });
  test('external entities and unsupported documents are rejected', () {
    expect(
      () => NfoInfo.parse(
        '<!DOCTYPE movie [<!ENTITY ext SYSTEM "file:///secret">]><movie><plot>&ext;</plot></movie>',
      ),
      throwsFormatException,
    );
    expect(() => NfoInfo.parse('<unrelated/>'), throwsFormatException);
  });
  test('local NAS scan reads sidecars and bad NFO falls back to filename', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-nfo-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/Original.2024.mp4').writeAsBytes([0]);
    await File('${dir.path}/Original.2024.nfo').writeAsString(
      '<movie><title>已有中文资料</title><plot>离线简介</plot><genre>剧情</genre></movie>',
    );
    final source = MediaSource(
      id: 'local',
      kind: SourceKind.local,
      name: 'NAS',
      location: dir.path,
    );
    expect((await LocalScanner().scan(source)).single.title, '已有中文资料');
    await File('${dir.path}/Original.2024.nfo').writeAsString('<broken');
    expect((await LocalScanner().scan(source)).single.title, 'Original');
  });
  test('WebDAV reads authenticated NFO without sending credentials to another origin', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var nfoRead = false;
    server.listen((r) async {
      if (r.method == 'PROPFIND') {
        r.response.statusCode = 207;
        r.response.write(
          '<d:multistatus xmlns:d="DAV:">${['Original.2024.mkv', 'movie.nfo'].map((n) => '<d:response><d:href>/dav/$n</d:href><d:propstat><d:prop><d:displayname>$n</d:displayname><d:getcontentlength>100</d:getcontentlength></d:prop></d:propstat></d:response>').join()}</d:multistatus>',
        );
      } else {
        nfoRead = true;
        expect(
          r.headers.value('Authorization'),
          'Basic ${base64Encode(utf8.encode('u:p'))}',
        );
        r.response.write(
          '<movie><title>远程中文电影</title><plot>NAS 已有刮削结果</plot></movie>',
        );
      }
      await r.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}/dav/');
    final client = WebDavClient(base, username: 'u', password: 'p');
    addTearDown(client.close);
    final items = await WebDavScanner().scan(
      MediaSource(
        id: 'dav',
        kind: SourceKind.webdav,
        name: 'NAS',
        location: base.toString(),
      ),
      client,
    );
    expect(nfoRead, isTrue);
    expect(items.single.title, '远程中文电影');
    expect(items.single.overview, 'NAS 已有刮削结果');
    await expectLater(
      client.readText(Uri.parse('http://other.test/nfo')),
      throwsA(isA<WebDavException>()),
    );
  });
}
