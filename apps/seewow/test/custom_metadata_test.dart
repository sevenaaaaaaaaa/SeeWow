import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/domain/metadata_language_draft.dart';
import 'package:seewow/domain/metadata_languages.dart';
import 'package:seewow/metadata/cover_generator.dart';
import 'package:seewow/metadata/custom_scraper.dart';
import 'package:seewow/metadata/metadata_transport.dart';

Future<Uint8List> testCoverBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 40, 60),
    ui.Paint()..color = const ui.Color(0xff123456),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 60);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _FailedSaveStore extends LibraryStore {
  _FailedSaveStore(Directory directory) : super(directory: directory);
  bool concurrentEdit = false;
  @override
  Future<void> save() async {
    items[0] = items[0].copyWith(position: 77);
    if (concurrentEdit)
      items[0] = items[0].copyWith(
        title: 'Newer edit',
        metadata: MediaMetadata.fromJson({
          ...items[0].metadata!.toJson(),
          'title': 'Newer edit',
        }),
      );
    throw StateError('fixture disk failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory dir;
  late Uint8List png;
  setUpAll(() async {
    png = await testCoverBytes();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-custom-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  MediaItem item({
    bool aiAllowed = true,
    String? poster,
    MediaMetadata? metadata,
  }) => MediaItem(
    id: 'a',
    sourceId: 'nas',
    kind: MediaKind.other,
    title: '课程 العربية བོད',
    locator: '/private/SECRET.mp4',
    overview: 'A study of nature.',
    position: 42,
    aiAllowed: aiAllowed,
    posterUrl: poster,
    metadata: metadata,
    httpHeaders: {'Authorization': 'MEDIA_SECRET'},
  );
  CustomScraperProfile profile(String base, {String details = ''}) =>
      CustomScraperProfile(
        id: 'course',
        name: '课程资料',
        category: '课程',
        baseUrl: base,
        kinds: ['other'],
        searchPath: 'lookup',
        detailsPath: details,
        detailsRoot: 'data',
        resultsPath: 'data.items',
        searchQuery: {
          'q': '{query}',
          'type': '{kind}',
          'category': '{category}',
          'lang': '{language}',
          'season': '{season}',
        },
        fields: {
          'id': 'key',
          'title': 'name',
          'overview': 'summary',
          'posterUrl': 'art.poster',
          'people': 'people',
          'ratings': 'ratings',
          'localized': 'translations',
          'year': 'year',
        },
      );
  test('custom JSON mapping preserves regional metadata and ignores playback fields', () async {
    final requests = <Uri>[];
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final record = {
      'key': 'course_1',
      'name': '本地课程',
      'summary': '简介',
      'year': '2025',
      'art': {'poster': 'https://images.example.test/poster.png'},
      'people': [
        {'name': '讲师', 'role': 'Teacher'},
      ],
      'ratings': [
        {'source': 'Campus', 'value': 4.5, 'scale': 5, 'votes': 10},
      ],
      'translations': {
        'ar-SA': {'title': 'درس'},
        'zh-TW': {'title': '課程'},
      },
      'playUrl': 'https://video.test/secret',
      'spider': 'never execute',
    };
    server.listen((r) async {
      requests.add(r.uri);
      expect(r.headers.value('Authorization'), 'Bearer SCRAPER_SECRET');
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'data': r.uri.path.endsWith('lookup')
              ? {
                  'items': [record],
                }
              : record,
        }),
      );
      await r.response.close();
    });
    final client = CustomScraperClient(
      profile('http://127.0.0.1:${server.port}/api', details: 'detail/{id}'),
      token: 'SCRAPER_SECRET',
    );
    addTearDown(client.close);
    final results = await client.search(
      item(),
      'A&B / العربية',
      language: 'ar-SA',
    );
    expect(requests.first.path, '/api/lookup');
    expect(requests.first.queryParameters['q'], 'A&B / العربية');
    expect(requests.first.queryParameters['category'], '课程');
    expect(requests.first.toString(), isNot(contains('SECRET')));
    final result = await client.details(results.single, item());
    expect(result.title, '本地课程');
    expect(result.provider, 'custom:course');
    expect(result.mediaType, 'other');
    expect(result.ratings.single.scale, 5);
    expect(result.localized['zh-TW']!.title, '課程');
    expect(jsonEncode(result.toJson()), isNot(contains('playUrl')));
    expect(jsonEncode(result.toJson()), isNot(contains('spider')));
    final store = LibraryStore(directory: dir)..items.add(item());
    await store.applyMetadata('a', result);
    expect(store.items.single.locator, item().locator);
    expect(store.items.single.position, 42);
    expect(store.items.single.title, '本地课程');
    store.dispose();
  });
  test(
    'type restrictions and invalid adapters fail before any HTTP call',
    () async {
      final client = CustomScraperClient(profile('http://127.0.0.1:1'));
      await expectLater(
        client.search(
          MediaItem(
            id: 'x',
            sourceId: 's',
            kind: MediaKind.movie,
            title: 'x',
            locator: '/a',
          ),
          'x',
        ),
        throwsFormatException,
      );
      client.close();
      for (final mutation in [
        {'searchPath': 'https://evil.test/a'},
        {'detailsPath': '../outside/{id}'},
        {
          'searchQuery': {'q': '{locator}'},
        },
        {
          'fields': {'title': 'eval(script)'},
        },
        {
          'fields': {'title': 'name', 'playUrl': 'url'},
        },
        {'authHeader': 'Host'},
        {'baseUrl': 'https://u:p@example.test'},
      ]) {
        final config = CustomScraperProfile.fromJson({
          ...profile('https://metadata.test').toJson(),
          ...mutation,
        });
        expect(config.validate, throwsFormatException);
      }
      expect(CustomScraperClient.at([1], '-1'), isNull);
    },
  );
  test(
    'details identity mismatches and invalid rating scales are rejected',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      var badScore = false;
      server.listen((r) async {
        final value = {
          'key': badScore ? 'ok' : 'wrong',
          'name': 'Other',
          if (badScore)
            'ratings': [
              {'source': 'R', 'value': 10, 'scale': 5},
            ],
        };
        r.response.write(jsonEncode({'data': value}));
        await r.response.close();
      });
      final client = CustomScraperClient(
        profile('http://127.0.0.1:${server.port}', details: 'detail/{id}'),
      );
      addTearDown(client.close);
      const candidate = MediaMetadata(
        id: 0,
        mediaType: 'other',
        title: 'Selected',
        externalIds: {'custom_id': 'ok'},
      );
      await expectLater(
        client.details(candidate, item()),
        throwsFormatException,
      );
      badScore = true;
      await expectLater(
        client.details(candidate, item()),
        throwsFormatException,
      );
    },
  );
  test('transport rejects redirects, oversized replies and cancels a stalled request', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final entered = Completer<void>();
    var redirected = 0;
    server.listen((r) async {
      if (r.uri.path == '/redirect') {
        r.response.statusCode = 302;
        r.response.headers.set('Location', '/stolen');
        await r.response.close();
      } else if (r.uri.path == '/large') {
        r.response.write(jsonEncode({'text': 'x' * 300}));
        await r.response.close();
      } else if (r.uri.path == '/wait') {
        entered.complete();
      } else {
        redirected++;
        await r.response.close();
      }
    });
    final transport = MetadataTransport();
    addTearDown(transport.close);
    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
    await expectLater(
      transport.json(url('/redirect'), headers: {'Authorization': 'PRIVATE'}),
      throwsFormatException,
    );
    expect(redirected, 0);
    await expectLater(
      transport.json(url('/large'), maxBytes: 50),
      throwsFormatException,
    );
    final pending = transport.json(url('/wait'));
    final checked = expectLater(pending, throwsA(isA<MetadataCancelled>()));
    await entered.future;
    transport.close();
    await checked;
  });
  test('scraper profiles and secrets stay separate, changes in endpoint never reuse a key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    final secrets = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('seewow/native'), (
          call,
        ) async {
          final key = call.arguments['key'] as String;
          if (call.method == 'secret.read') return secrets[key];
          if (call.method == 'secret.write') {
            secrets[key] = call.arguments['value'];
            return true;
          }
          if (call.method == 'secret.delete') secrets.remove(key);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('seewow/native'), null),
    );
    final repo = CustomScraperRepository();
    final first = profile('https://first.test/api');
    await repo.save(first, token: 'PRIVATE');
    expect(secrets[CustomScraperRepository.key], isNot(contains('PRIVATE')));
    expect((await repo.client(first)).token, 'PRIVATE');
    final second = profile('https://second.test/api');
    await repo.save(second);
    final client = await repo.client(second);
    expect(client.token, isEmpty);
    client.close();
    expect((await repo.load()).single.baseUrl, second.baseUrl);
    await repo.save(second, token: 'NEW');
    await repo.save(second, clearToken: true);
    expect(secrets[second.credentialKey], isNull);
    await repo.remove(second);
    expect(await repo.load(), isEmpty);
  });
  test('cover request contains only reviewed prompt and validates base64 raster output', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    Map? sent;
    server.listen((r) async {
      sent = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      expect(r.headers.value('Authorization'), 'Bearer IMAGE_SECRET');
      r.response.write(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(png)},
          ],
        }),
      );
      await r.response.close();
    });
    final generator = CoverGenerator(
      CoverGenerationConfig(
        endpoint: 'http://127.0.0.1:${server.port}/v1/images/generations',
        model: 'fixture-image',
      ),
    );
    // A second client verifies authentication stays dedicated to this service.
    final authenticated = CoverGenerator(
      generator.config,
      token: 'IMAGE_SECRET',
    );
    addTearDown(generator.close);
    addTearDown(authenticated.close);
    final result = await authenticated.generate(
      item(),
      'Original nature illustration',
    );
    expect(result.bytes, png);
    expect(sent!.keys.toSet(), {'model', 'prompt', 'n', 'size'});
    expect(jsonEncode(sent), isNot(contains('MEDIA_SECRET')));
    expect(jsonEncode(sent), isNot(contains('/private')));
    expect(sent!['prompt'], 'Original nature illustration');
  });
  test('cover generation refuses restricted sources, URL-only replies and non-raster content', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    var calls = 0, mode = 0;
    server.listen((r) async {
      calls++;
      await r.drain<void>();
      r.response.write(
        jsonEncode({
          'data': [
            mode == 0
                ? {'url': 'http://127.0.0.1/never-fetch'}
                : {'b64_json': base64Encode(utf8.encode('<svg></svg>'))},
          ],
        }),
      );
      await r.response.close();
    });
    final generator = CoverGenerator(
      CoverGenerationConfig(
        endpoint: 'http://127.0.0.1:${server.port}/images/generations',
        model: 'fixture',
      ),
    );
    addTearDown(generator.close);
    await expectLater(
      generator.generate(item(aiAllowed: false), 'prompt'),
      throwsFormatException,
    );
    expect(calls, 0);
    await expectLater(
      generator.generate(item(), 'prompt'),
      throwsFormatException,
    );
    mode = 1;
    await expectLater(
      generator.generate(item(), 'prompt'),
      throwsFormatException,
    );
    expect(calls, 2);
    await expectLater(
      validateCoverBytes(Uint8List.fromList([137, 80, 78, 71, 0, 0, 0, 0])),
      throwsFormatException,
    );
  });
  test('generated cover saves independently, survives rescan and source match with provenance', () async {
    final store = LibraryStore(directory: dir)..items.add(item());
    final before = metadataSnapshot(store.items.single);
    await store.applyGeneratedCover(
      itemId: 'a',
      before: before,
      bytes: png,
      model: 'fixture',
      createdAt: DateTime.utc(2026),
    );
    final saved = store.items.single;
    expect(saved.hasGeneratedCover, isTrue);
    expect(saved.position, 42);
    expect(saved.title, item().title);
    expect(await File(saved.posterUrl!).readAsBytes(), png);
    expect(saved.metadata!.reviewed, isFalse);
    final reloaded = LibraryStore(directory: dir);
    await reloaded.load();
    expect(reloaded.items.single.hasGeneratedCover, isTrue);
    reloaded.dispose();
    final source = MediaSource(
      id: 'nas',
      kind: SourceKind.local,
      name: 'Files',
      location: '/folder',
    );
    store.sources.add(source);
    store.scanner = (_) async => [item()];
    await store.rescan(source);
    expect(store.items.single.posterUrl, saved.posterUrl);
    expect(store.items.single.hasGeneratedCover, isTrue);
    await store.applyMetadata(
      'a',
      const MediaMetadata(
        id: 0,
        provider: 'custom:fixture',
        mediaType: 'other',
        title: 'Source title',
      ),
    );
    expect(store.items.single.hasGeneratedCover, isTrue);
    expect(store.items.single.title, 'Source title');
    store.dispose();
  });
  test('cover confirmation refuses stale metadata, unauthorized replacement and AI isolation', () async {
    final store = LibraryStore(directory: dir)..items.add(item());
    final before = metadataSnapshot(store.items.single);
    store.items[0] = item().copyWith(title: 'Changed');
    await expectLater(
      store.applyGeneratedCover(
        itemId: 'a',
        before: before,
        bytes: png,
        model: 'fixture',
        createdAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    store.items[0] = item(poster: 'https://poster.test/a');
    await expectLater(
      store.applyGeneratedCover(
        itemId: 'a',
        before: metadataSnapshot(store.items.single),
        bytes: png,
        model: 'fixture',
        createdAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    store.items[0] = item(aiAllowed: false);
    await expectLater(
      store.applyGeneratedCover(
        itemId: 'a',
        before: metadataSnapshot(store.items.single),
        bytes: png,
        model: 'fixture',
        createdAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    expect(await Directory('${dir.path}/covers').exists(), isFalse);
    store.dispose();
  });
  test('stalled metadata response hits the total deadline', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      r.response.write('{');
      await r.response.flush();
    });
    final http = MetadataTransport(timeout: const Duration(milliseconds: 150));
    addTearDown(http.close);
    await expectLater(
      http.json(Uri.parse('http://127.0.0.1:${server.port}/wait')),
      throwsFormatException,
    );
  });
  test('failed cover persistence removes its owned file and rolls back art while preserving progress', () async {
    final store = _FailedSaveStore(dir)..items.add(item());
    final original = store.items.single;
    await expectLater(
      store.applyGeneratedCover(
        itemId: 'a',
        before: metadataSnapshot(original),
        bytes: png,
        model: 'fixture',
        createdAt: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(store.items.single.posterUrl, isNull);
    expect(store.items.single.metadata, isNull);
    expect(store.items.single.position, 77);
    expect(store.items.single.locator, original.locator);
    expect(store.items.single.httpHeaders, original.httpHeaders);
    expect(await Directory('${dir.path}/covers').list().toList(), isEmpty);
    store.dispose();
  });
  test('failed cover save does not roll back a newer metadata edit or delete art it references', () async {
    final store = _FailedSaveStore(dir)..concurrentEdit = true;
    store.items.add(item());
    await expectLater(
      store.applyGeneratedCover(
        itemId: 'a',
        before: metadataSnapshot(store.items.single),
        bytes: png,
        model: 'fixture',
        createdAt: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(store.items.single.title, 'Newer edit');
    expect(store.items.single.hasGeneratedCover, isTrue);
    expect(await File(store.items.single.posterUrl!).exists(), isTrue);
    store.dispose();
  });
  test('custom rematches retain regional text only for the same provider and stable work ID', () {
    const previous = MediaMetadata(
      id: 0,
      provider: 'custom:course',
      mediaType: 'other',
      title: 'First',
      externalIds: {'custom_id': 'first'},
      localized: {'zh-HK': LocalizedMetadata(title: '第一作品')},
    );
    MediaMetadata rematch(String provider, String id) => MediaMetadata(
      id: 0,
      provider: provider,
      mediaType: 'other',
      title: 'New',
      externalIds: {'custom_id': id},
    );
    expect(
      retainLanguages(
        rematch('custom:course', 'first'),
        previous,
      ).localized['zh-HK']!.title,
      '第一作品',
    );
    for (final next in [
      rematch('custom:course', 'second'),
      rematch('custom:other', 'first'),
      rematch('custom:course', ''),
      rematch('tmdb', 'first'),
    ]) {
      expect(retainLanguages(next, previous).localized, isEmpty);
    }
    expect(retainLanguages(previous, previous).localized, previous.localized);
  });
}
