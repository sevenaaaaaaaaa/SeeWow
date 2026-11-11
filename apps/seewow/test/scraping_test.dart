import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/data/local_scanner.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/nfo_reader.dart';
import 'package:seewow/metadata/subtitles.dart';
import 'package:seewow/metadata/tmdb_client.dart';
import 'package:seewow/sources/subscription_reader.dart';

class _DownloadReader extends SubscriptionReader {
  _DownloadReader(SecurityContext context)
    : super(securityContext: context, maxBytes: 2 * 1024 * 1024);
  @override
  Future<SubscriptionText> read(
    String source, {
    bool allowLocalNetwork = false,
  }) => super.read(source, allowLocalNetwork: true);
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-scraping-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('source-labelled ratings, people, original titles and images survive roundtrip', () {
    const data = MediaMetadata(
      id: 42,
      mediaType: 'movie',
      title: '千と千尋の神隠し',
      originalTitle: '千と千尋の神隠し',
      originalLanguage: 'ja',
      language: 'zh-TW',
      countries: ['JP'],
      people: [
        MediaPerson(name: '宮崎駿', role: 'Director', department: 'Directing'),
      ],
      ratings: [
        MediaRating(source: 'Critics', value: 95, scale: 100, votes: 20),
      ],
      externalIds: {'imdb': 'tt0245429'},
      artworks: [
        MediaArtwork(url: 'https://image.test/ja.jpg', language: 'ja'),
      ],
    );
    final restored = MediaMetadata.fromJson(
      jsonDecode(jsonEncode(data.withArtwork(true).toJson()))
          as Map<String, dynamic>,
    );
    expect(restored.people.single.name, '宮崎駿');
    expect(restored.ratings.single.scale, 100);
    expect(restored.originalLanguage, 'ja');
    expect(restored.artworks.single.language, 'ja');
    expect(restored.externalIds['imdb'], 'tt0245429');
    expect(restored.replaceArtwork, isTrue);
    expect(
      MediaMetadata.fromJson({'id': 1, 'mediaType': 'movie', 'title': 'Legacy'})
          .provider,
      'tmdb',
    );
  });
  test('NFO handles Unicode, credits, separate rating scales and safe relative art', () {
    final info = NfoInfo.parse(
      '<musicvideo><title>موسيقى 音楽</title><originaltitle>Original</originaltitle><originallanguage>ar</originallanguage><country>日本</country><director>导演</director><actor><name>俳優</name><role>本人</role></actor><ratings><rating name="critics" max="100" default="true"><value>95</value><votes>12</votes></rating><rating name="audience" max="10"><value>8.2</value></rating></ratings><uniqueid type="imdb">tt123</uniqueid><thumb aspect="poster">art/cover.jpg</thumb></musicvideo>',
      directory: Uri.parse('file:///media/concert/'),
    );
    expect(info.rating, 9.5);
    expect(info.ratings.map((r) => r.scale), [100, 10]);
    expect(info.people.map((p) => p.name), containsAll(['导演', '俳優']));
    expect(
      info.asMetadata(fallbackTitle: 'file', mediaType: 'movie').posterUrl,
      '/media/concert/art/cover.jpg',
    );
    expect(
      NfoInfo.artwork('../private.jpg', Uri.parse('file:///media/concert/')),
      isNull,
    );
    expect(
      NfoInfo.artwork(
        'file:///private/secret',
        Uri.parse('https://nas.test/media/'),
      ),
      isNull,
    );
  });
  test(
    'UTF-16 sidecars and changing NFO refresh without replacing reviewed edits',
    () async {
      final mediaDir = await Directory('${dir.path}/media').create();
      await File('${mediaDir.path}/Film.mp4').writeAsBytes([0]);
      final sidecar = File('${mediaDir.path}/Film.nfo');
      const text =
          '<movie><title>电影</title><actor><name>演员</name></actor></movie>';
      await sidecar.writeAsBytes([
        255,
        254,
        for (final unit in text.codeUnits) ...[unit & 255, unit >> 8],
      ]);
      final source = MediaSource(
        id: 's',
        kind: SourceKind.local,
        name: 'Home',
        location: mediaDir.path,
      );
      final store = LibraryStore(directory: dir)
        ..sources.add(source)
        ..scanner = LocalScanner().scan;
      await store.rescan(source);
      expect(store.items.single.title, '电影');
      expect(store.items.single.metadata!.people.single.name, '演员');
      await sidecar.writeAsString('<movie><title>Updated</title></movie>');
      await store.rescan(store.sources.single);
      expect(store.items.single.title, 'Updated');
      await store.applyMetadata(
        store.items.single.id,
        const MediaMetadata(
          id: 0,
          provider: 'local',
          mediaType: 'movie',
          title: 'Reviewed',
        ),
      );
      await sidecar.writeAsString(
        '<movie><title>Changed again</title></movie>',
      );
      await store.rescan(store.sources.single);
      expect(store.items.single.title, 'Reviewed');
      store.dispose();
    },
  );
  test('episode-specific corrections never rename the series or other episodes; audio accepts local metadata', () async {
    final store = LibraryStore(directory: dir)
      ..items.addAll([
        for (final n in [1, 2])
          MediaItem(
            id: '$n',
            sourceId: 's',
            kind: MediaKind.episode,
            title: 'Episode $n',
            showTitle: 'Show',
            season: 0,
            episode: n,
            locator: '/$n.mkv',
          ),
        MediaItem(
          id: 'audio',
          sourceId: 's',
          kind: MediaKind.audio,
          title: 'Track',
          locator: '/music.flac',
        ),
      ]);
    await store.applyMetadata(
      '1',
      const MediaMetadata(
        id: 12,
        mediaType: 'episode',
        title: '特別篇',
        duration: 1200,
      ),
    );
    expect(store.items.first.title, '特別篇');
    expect(store.items.first.libraryTitle, 'Show');
    expect(store.items.first.displayTitle, 'Show  S00E01');
    expect(store.items[1].metadata, isNull);
    await store.applyMetadata(
      'audio',
      const MediaMetadata(
        id: 0,
        provider: 'local',
        mediaType: 'audio',
        title: '音楽',
      ),
    );
    expect(store.items.last.title, '音楽');
    store.dispose();
  });
  test('sidecar subtitles match exact video stems and include scripts and image formats', () async {
    final video = File('${dir.path}/课程.mp4');
    await video.writeAsBytes([0]);
    for (final name in [
      '课程.zh-cn.ass',
      '课程.ar.srt',
      '课程.sup',
      '课程2.en.srt',
      'Other.srt',
    ]) {
      await File('${dir.path}/$name').writeAsBytes([0]);
    }
    final results = await SubtitleFiles.discover(video.path);
    expect(
      results.map((r) => r.name),
      containsAll(['课程.zh-cn.ass', '课程.ar.srt', '课程.sup']),
    );
    expect(results, hasLength(3));
    expect(await SubtitleFiles.discover('https://cdn.test/movie.mp4'), isEmpty);
  });

  test(
    'subtitle caches isolate sources and preserve regional language variants',
    () async {
      final root = Directory('${dir.path}/cache');
      final cache = SubtitleCache(directory: root);
      final a = MediaItem(
        id: 'same',
        sourceId: 'one',
        kind: MediaKind.movie,
        title: 'A',
        locator: '/a.mp4',
      );
      final b = MediaItem(
        id: 'same',
        sourceId: 'two',
        kind: MediaKind.movie,
        title: 'B',
        locator: '/b.mp4',
      );
      const text = '1\n00:00:00,000 --> 00:00:01,000\n繁體中文';
      final saved = await cache.save(a, text, language: 'zh-tw');
      expect(saved.path, startsWith(root.path));
      expect((await cache.list(a)).single.name, '缓存字幕 · zh-tw');
      expect(await cache.list(b), isEmpty);
      final malicious = await cache.save(a, text, language: '../../escape');
      expect(malicious.path, startsWith(root.path));
      expect(malicious.name, contains('und'));
      await cache.clear();
      expect(await cache.list(a), isEmpty);
    },
  );

  group('TMDB locale and identity', () {
    late HttpServer server;
    final requests = <Uri>[];
    var wrongEpisode = false;
    setUp(() async {
      requests.clear();
      wrongEpisode = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requests.add(req.uri);
        expect(req.headers.value('authorization'), 'Bearer private-key');
        req.response.headers.contentType = ContentType.json;
        final localized = req.uri.queryParameters['language'] == 'ja-JP';
        final detail = <String, dynamic>{
          'id': 42,
          'title': '日本語題名',
          'name': '番組',
          'original_title': 'Original',
          'original_name': 'Original Show',
          'original_language': 'ja',
          'overview': localized ? '' : 'Fallback overview',
          'vote_count': 20,
          'vote_average': 8.5,
          'credits': {
            'cast': [
              {'id': 7, 'name': '俳優', 'character': '主人公'},
            ],
            'crew': [
              {'name': '監督', 'job': 'Director', 'department': 'Directing'},
            ],
          },
          'images': {
            'posters': [
              {'file_path': '/ja.jpg', 'iso_639_1': 'ja'},
            ],
          },
          'external_ids': {'imdb_id': 'tt123', 'tvdb_id': 123},
        };
        if (req.uri.path.contains('/search/')) {
          req.response.write(
            jsonEncode({
              'results': [detail],
              'total_pages': 2,
            }),
          );
        } else if (req.uri.path.contains('/episode/')) {
          req.response.write(
            jsonEncode({
              ...detail,
              'id': 55,
              'season_number': 0,
              'episode_number': wrongEpisode ? 2 : 1,
              'runtime': 22,
              'air_date': '2024-01-01',
            }),
          );
        } else {
          req.response.write(jsonEncode(detail));
        }
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));
    TmdbClient client() => TmdbClient(
      'private-key',
      base: Uri.parse('http://127.0.0.1:${server.port}/3'),
      locale: const MetadataLocale(
        language: 'ja-JP',
        region: 'JP',
        fallback: 'en-US',
      ),
    );
    test('language, region, year and pagination reach the provider; fallback only fills missing fields', () async {
      final c = client();
      addTearDown(c.close);
      final result = await c.search('原題', year: 2024, page: 2);
      expect(requests.first.queryParameters, containsPair('region', 'JP'));
      expect(requests.first.queryParameters, containsPair('year', '2024'));
      final detail = await c.details(result.single);
      expect(detail.title, '日本語題名');
      expect(detail.overview, 'Fallback overview');
      expect(detail.originalTitle, 'Original');
      expect(detail.people, hasLength(2));
      expect(detail.ratings.single.source, 'TMDB');
      expect(detail.externalIds['imdb'], 'tt123');
      expect(detail.artworks.single.language, 'ja');
      expect(detail.notes, isNotEmpty);
      expect(requests.last.queryParameters['language'], 'en-US');
    });
    test('disabled language fallback keeps missing text empty and sends a valid image language filter', () async {
      final c = client();
      addTearDown(c.close);
      c.locale = const MetadataLocale(language: 'ja-JP', fallback: '');
      final detail = await c.details(
        const MediaMetadata(id: 42, mediaType: 'movie', title: 'Movie'),
      );
      expect(detail.overview, isEmpty);
      expect(requests, hasLength(1));
      expect(
        requests.single.queryParameters['include_image_language'],
        'ja,null',
      );
    });
    test('specials use season zero, preserve series ID and reject mismatched episode identity', () async {
      final c = client();
      addTearDown(c.close);
      final episode = await c.episodeDetails(
        const MediaMetadata(id: 42, mediaType: 'tv', title: 'Show'),
        0,
        1,
      );
      expect(episode.mediaType, 'episode');
      expect(episode.duration, 1320);
      expect(episode.externalIds['tmdb_series'], '42');
      expect(requests.single.path, '/3/tv/42/season/0/episode/1');
      wrongEpisode = true;
      await expectLater(
        c.episodeDetails(
          const MediaMetadata(id: 42, mediaType: 'tv', title: 'Show'),
          0,
          1,
        ),
        throwsFormatException,
      );
    });
  });

  group('OpenSubtitles transport', () {
    late HttpServer api, cdn;
    final requests = <({Uri uri, String? key, String? token, String body})>[];
    var html = false;
    setUp(() async {
      html = false;
      requests.clear();
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/subscription_localhost_cert.pem')
        ..usePrivateKey('test/fixtures/subscription_localhost_key.pem');
      cdn = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      cdn.listen((req) async {
        expect(req.headers.value('authorization'), isNull);
        expect(req.headers.value('api-key'), isNull);
        req.response.write(
          html
              ? '<html>error</html>'
              : '1\n00:00:00,000 --> 00:00:02,000\n字幕 مرحبا\n',
        );
        await req.response.close();
      });
      api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        requests.add((
          uri: req.uri,
          key: req.headers.value('api-key'),
          token: req.headers.value('authorization'),
          body: body,
        ));
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode(
            req.uri.path.endsWith('/download')
                ? {
                    'link': 'https://127.0.0.1:${cdn.port}/sub.srt',
                    'remaining': 4,
                  }
                : {
                    'total_pages': 2,
                    'data': [
                      {
                        'attributes': {
                          'language': 'ar',
                          'release': 'WEB-DL',
                          'hearing_impaired': true,
                          'files': [
                            {'file_id': 123, 'file_name': 'Movie.ar.srt'},
                          ],
                        },
                      },
                    ],
                  },
          ),
        );
        await req.response.close();
      });
    });
    tearDown(() async {
      await api.close(force: true);
      await cdn.close(force: true);
    });
    test('episode search uses parent IDs, language codes and release information; downloads never forward secrets', () async {
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('test/fixtures/subscription_test_ca.pem');
      final client = OpenSubtitlesClient(
        'api-secret',
        token: 'account-secret',
        base: Uri.parse('http://127.0.0.1:${api.port}/api/v1'),
        reader: _DownloadReader(trust),
      );
      addTearDown(client.close);
      final item = MediaItem(
        id: 'ep',
        sourceId: 's',
        kind: MediaKind.episode,
        title: 'Episode',
        showTitle: 'Show',
        season: 0,
        episode: 1,
        locator: '/private/file',
        metadata: const MediaMetadata(
          id: 42,
          mediaType: 'tv',
          title: 'Show',
          externalIds: {'imdb': 'tt123'},
        ),
      );
      final results = await client.search(item, languages: 'ar, zh-cn');
      expect(requests.first.uri.queryParameters['parent_imdb_id'], '123');
      expect(requests.first.uri.queryParameters['languages'], 'ar,zh-cn');
      expect(requests.first.uri.queryParameters['season_number'], '0');
      expect(requests.first.key, 'api-secret');
      expect(requests.first.token, 'Bearer account-secret');
      expect(results.single.release, 'WEB-DL');
      expect(results.single.hearingImpaired, isTrue);
      expect(await client.download(results.single), contains('مرحبا'));
      expect(client.remaining, 4);
      expect(jsonDecode(requests.last.body)['file_id'], 123);
      html = true;
      await expectLater(client.download(results.single), throwsFormatException);
    });
    test(
      'account base URLs cannot expand credential access to arbitrary servers',
      () {
        expect(
          OpenSubtitlesClient.officialBase(
            Uri.parse('https://vip-api.opensubtitles.com'),
          ),
          isTrue,
        );
        for (final url in [
          'https://evil.test',
          'http://api.opensubtitles.com',
          'https://api.opensubtitles.com.evil.test',
          'https://user:pass@api.opensubtitles.com',
        ]) {
          expect(OpenSubtitlesClient.officialBase(Uri.parse(url)), isFalse);
        }
      },
    );
  });
}
