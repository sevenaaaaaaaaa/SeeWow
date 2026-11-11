import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/domain/iptv.dart';
import 'package:seewow/domain/subscription.dart';
import 'package:seewow/sources/subscription_reader.dart';

class MemorySubscriptionReader extends SubscriptionReader {
  final documents = <String, String>{};
  final requests = <String>[];
  @override
  Future<SubscriptionText> read(
    String source, {
    bool allowLocalNetwork = false,
  }) async {
    requests.add(source);
    final text = documents[source];
    if (text == null) throw const FormatException('unavailable');
    return SubscriptionText(text, Uri.parse(source));
  }
}

void main() {
  SubscriptionPreview parse(String text) => SubscriptionParser.parse(
    text,
    uri: Uri.parse('https://example.test/config/main.json'),
    playlistId: 'p',
  );

  test('depot and TVBox live references are data and are not fetched', () {
    final depot = parse(
      '{"urls":[{"name":"Family","url":"./family.json"},{"url":"file:///private/secret"}]}',
    );
    expect(
      depot.links.single.uri.toString(),
      'https://example.test/config/family.json',
    );
    expect(depot.channels, isEmpty);
    expect(depot.warnings.single, contains('本地文件'));
    final live = parse(
      '{"spider":"https://evil.test/plugin.jar","sites":[{"api":"csp_Test"}],"lives":[{"name":"Home","url":"../live.m3u","epg":"./guide.xml"}]}',
    );
    expect(live.links.single.uri.toString(), 'https://example.test/live.m3u');
    expect(live.links.single.epgUrl, 'https://example.test/config/guide.xml');
    expect(live.warnings.single, contains('不会下载或执行'));
  });
  test('M3U resolves stream, logo and guide paths without executing player options', () {
    final data = parse(
      '#EXTM3U url-tvg="https://guide.test/epg.xml"\n#EXTINF:-1 tvg-id="a" tvg-logo="./logo.png" group-title="Home",A\n#EXTVLCOPT:http-user-agent=Injected\n./a.m3u8',
    );
    expect(data.channels.single.url, 'https://example.test/config/a.m3u8');
    expect(data.channels.single.logo, 'https://example.test/config/logo.png');
    expect(data.epgUrl, 'https://guide.test/epg.xml');
    expect(data.warnings.single, contains('忽略'));
  });
  test(
    'TXT groups preserve commas inside the URL and reject executable schemes',
    () {
      final data = parse(
        'Home,#genre#\nA,https://stream.test/a?values=1,2\nBad,javascript:evil()\nOther,#genre#\nB,https://stream.test/b',
      );
      expect(data.channels.map((c) => c.group), ['Home', 'Other']);
      expect(data.channels.first.url, contains('values=1,2'));
      expect(data.warnings, isNotEmpty);
    },
  );
  test(
    'inline live groups and simple JSON channels preserve IDs and deduplicate',
    () {
      final data = parse(
        '{"lives":[{"name":"Home","channels":[{"name":"A","urls":["https://x.test/a","https://x.test/a"]}]}]}',
      );
      expect(data.channels.single.group, 'Home');
      expect(
        parse('[{"name":"A","url":"https://x.test/a","group":"Home"}]')
            .channels
            .single
            .id,
        data.channels.single.id,
      );
    },
  );
  test('plugin-only configs cannot be imported, and HLS, HTML and malformed JSON are rejected', () {
    expect(parse('{"sites":[],"spider":"plugin.jar"}').channels, isEmpty);
    for (final text in [
      '{"bad":',
      '<html>foo,bar</html>',
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\na.ts',
    ]) {
      expect(() => parse(text), throwsFormatException);
    }
  });
  test(
    'stable identity survives order changes and rejects excessive entries',
    () {
      final first = parse('A,https://x.test/a\nB,https://x.test/b');
      final next = parse('B,https://x.test/b\nA,https://x.test/a');
      expect(first.channels.first.id, next.channels.last.id);
      expect(
        () => parse(List.filled(10001, 'A,https://x.test/a').join('\n')),
        throwsFormatException,
      );
    },
  );

  group('subscription storage', () {
    late Directory dir;
    late MemorySubscriptionReader reader;
    late IPTVStore store;
    const source = 'https://example.test/list';
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('seewow-subscription-');
      reader = MemorySubscriptionReader()
        ..documents[source] = 'A,https://x.test/a\nB,https://x.test/b';
      store = IPTVStore(directory: dir, reader: reader);
    });
    tearDown(() async {
      store.dispose();
      await dir.delete(recursive: true);
    });
    test(
      'preview is read-only and import commits exactly the approved data',
      () async {
        final data = await store.preview(source);
        expect(store.playlists, isEmpty);
        reader.documents[source] = 'Changed,https://x.test/new';
        expect(
          await store.importPreview(data, name: 'Home', source: source),
          isTrue,
        );
        expect(reader.requests, [source]);
        expect(store.channels.map((c) => c.name), ['A', 'B']);
        final restored = IPTVStore(directory: dir);
        await restored.load();
        expect(
          restored.channels.map((c) => c.id),
          store.channels.map((c) => c.id),
        );
        restored.dispose();
      },
    );
    test('reload migrates legacy favourites and keeps old data when format changes', () async {
      await store.addPlaylist(name: 'Home', source: source);
      final playlist = store.playlists.single;
      final channel = store.channels.first;
      store.channels[0] = IPTVChannel(
        id: 'old-0000',
        playlistId: playlist.id,
        name: channel.name,
        url: channel.url,
      );
      store.favorites.add('old-0000');
      store.recents.add('old-0000');
      reader.documents[source] = 'B,https://x.test/b\nA,https://x.test/a';
      await store.reload(playlist);
      expect(store.favorites.single, store.channels.last.id);
      expect(store.recents.single, store.channels.last.id);
      reader.documents[source] =
          '{"urls":[{"name":"New","url":"https://else.test/config"}]}';
      await store.reload(store.playlists.single);
      expect(store.channels.map((c) => c.name), ['B', 'A']);
      expect(store.toast, contains('保留'));
      expect(reader.requests, isNot(contains('https://else.test/config')));
    });
    test('source URLs and error messages never expose tokens through failed refresh', () async {
      const secretSource = 'https://example.test/list?token=PRIVATE';
      reader.documents[secretSource] = reader.documents[source]!;
      await store.addPlaylist(name: 'Home', source: secretSource);
      reader.documents.remove(secretSource);
      await store.reload(store.playlists.single);
      expect(store.toast, isNot(contains('PRIVATE')));
      expect(store.channels, hasLength(2));
    });
    test('guides with the same channel ID are scoped to each subscription and can be removed', () async {
      for (final title in ['One', 'Two']) {
        final epg = 'https://example.test/$title.xml';
        reader.documents[epg] =
            '<tv><programme channel="same" start="20990101000000 +0000" stop="20990101010000 +0000"><title>$title</title></programme></tv>';
        final data = parse(
          '#EXTM3U\n#EXTINF:-1 tvg-id="same",A\nhttps://x.test/a',
        );
        expect(
          await store.importPreview(data, name: title, epgUrl: epg),
          isTrue,
        );
      }
      expect(store.guideFor(store.channels.first).single.title, 'One');
      expect(store.guideFor(store.channels.last).single.title, 'Two');
      expect(await store.setEpgUrl(store.playlists.first, ''), isTrue);
      expect(store.playlists.first.epgUrl, isNull);
      expect(store.guideFor(store.channels.first), isEmpty);
      expect(store.guideFor(store.channels.last).single.title, 'Two');
    });
    test('LAN permission is persisted and plugin-only previews cannot be committed', () async {
      await store.addPlaylist(
        name: 'Home',
        source: source,
        allowLocalNetwork: true,
      );
      final restored = IPTVStore(directory: dir);
      await restored.load();
      expect(restored.playlists.single.allowLocalNetwork, isTrue);
      expect(
        await store.importPreview(
          parse('{"spider":"bad.jar","sites":[]}'),
          name: 'bad',
        ),
        isFalse,
      );
      expect(store.playlists, hasLength(1));
      restored.dispose();
    });
  });

  group('bounded reader', () {
    late HttpServer server;
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('seewow-reader-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        switch (req.uri.path) {
          case '/redirect':
            req.response.statusCode = 302;
            req.response.headers.set('location', '/normal');
          case '/file':
            req.response.statusCode = 302;
            req.response.headers.set('location', 'file:///private/secret');
          case '/large':
            req.response.add(List.filled(200, 65));
          case '/gzip':
            req.response.headers.set('content-encoding', 'gzip');
            req.response.add(gzip.encode(List.filled(200, 65)));
          case '/slow':
            return;
          default:
            req.response.write('A,https://example.test/a');
        }
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    String url(String path) => 'http://127.0.0.1:${server.port}$path';
    test('local network requires an explicit opt-in and redirects cannot read files', () async {
      const reader = SubscriptionReader();
      await expectLater(reader.read(url('/normal')), throwsFormatException);
      final data = await reader.read(url('/redirect'), allowLocalNetwork: true);
      expect(data.uri.path, '/normal');
      expect(data.text, startsWith('A,'));
      await expectLater(
        reader.read(url('/file'), allowLocalNetwork: true),
        throwsFormatException,
      );
    });
    test(
      'limits apply to local, chunked and decompressed response bodies',
      () async {
        const reader = SubscriptionReader(maxBytes: 100);
        final file = File('${dir.path}/large.txt');
        await file.writeAsString('a' * 200);
        await expectLater(reader.read(file.path), throwsFormatException);
        for (final path in ['/large', '/gzip']) {
          await expectLater(
            reader.read(url(path), allowLocalNetwork: true),
            throwsFormatException,
          );
        }
      },
    );
    test('one deadline covers a stalled response', () async {
      const reader = SubscriptionReader(timeout: Duration(milliseconds: 150));
      await expectLater(
        reader.read(url('/slow'), allowLocalNetwork: true),
        throwsFormatException,
      );
    });
    test('HTTPS uses TLS with certificate verification and a pinned resolved address', () async {
        // Synthetic localhost-only fixtures; server certificate expires Jan 2029.
        // Regenerate these test credentials when renewing, never use in production.
      final cert = File('test/fixtures/subscription_localhost_cert.pem')
          .readAsBytesSync();
      final key = File('test/fixtures/subscription_localhost_key.pem')
          .readAsBytesSync();
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKeyBytes(key);
      final secureServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(() => secureServer.close(force: true));
      secureServer.listen((req) async {
        req.response.write('Secure,https://example.test/video');
        await req.response.close();
      });
      final endpoint = 'https://127.0.0.1:${secureServer.port}/list';
        final trusted = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('test/fixtures/subscription_test_ca.pem');
      final data = await SubscriptionReader(securityContext: trusted)
          .read(endpoint, allowLocalNetwork: true);
      expect(data.text, startsWith('Secure,'));
      await expectLater(
        const SubscriptionReader().read(endpoint, allowLocalNetwork: true),
        throwsFormatException,
      );
    });
    test('private and mapped IPv6 addresses are not public endpoints', () {
      for (final ip in [
        '127.0.0.1',
        '192.168.1.2',
        '169.254.169.254',
        '100.64.0.1',
        '::1',
        'fc00::1',
        '::ffff:192.168.1.2',
      ]) {
        expect(
          SubscriptionReader.isLocalAddress(InternetAddress(ip)),
          isTrue,
          reason: ip,
        );
      }
      expect(
        SubscriptionReader.isLocalAddress(InternetAddress('8.8.8.8')),
        isFalse,
      );
      expect(
        SubscriptionReader.isLocalAddress(
          InternetAddress('2606:4700:4700::1111'),
        ),
        isFalse,
      );
    });
  });
}
