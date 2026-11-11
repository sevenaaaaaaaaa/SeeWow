import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/domain/metadata_languages.dart';
import 'package:seewow/domain/metadata_language_draft.dart';
import 'package:seewow/domain/library_intelligence.dart';
import 'package:seewow/domain/filename_parser.dart';
import 'package:seewow/domain/iptv.dart';
import 'package:seewow/metadata/local_metadata_translation.dart';
import 'package:seewow/metadata/tmdb_client.dart';

void main() {
  MediaItem item({
    String id = 'a',
    MediaMetadata? metadata,
    bool aiAllowed = true,
  }) => MediaItem(
    id: id,
    sourceId: 'nas',
    kind: MediaKind.movie,
    title: 'Original',
    locator: '/private/video.mkv?token=SECRET',
    metadata: metadata,
    aiAllowed: aiAllowed,
    httpHeaders: {'Authorization': 'PRIVATE'},
  );
  const base = MediaMetadata(
    id: 42,
    mediaType: 'movie',
    title: 'Original',
    overview: 'A family travels home.',
    language: 'en-US',
  );
  test('Hong Kong and Taiwan remain separate; regional scripts and search aliases survive storage', () {
    final metadata = base.withLanguages(
      {
        'zh-HK': const LocalizedMetadata(title: '港版片名', provider: 'tmdb'),
        'zh-TW': const LocalizedMetadata(title: '台版片名', provider: 'tmdb'),
        'bo-CN': const LocalizedMetadata(
          title: 'བོད་ཡིག',
          titleOrigin: 'machine',
          engine: 'local',
        ),
      },
      alternatives: {
        'RU': ['Русское название'],
      },
    );
    final restored = MediaMetadata.fromJson(
      jsonDecode(jsonEncode(metadata.toJson())) as Map<String, dynamic>,
    );
    expect(restored.localized['zh-HK']!.title, '港版片名');
    expect(restored.localized['zh-TW']!.title, '台版片名');
    expect(restored.localized['bo-CN']!.titleOrigin, 'machine');
    for (final term in ['港版片名', '台版片名', 'བོད་ཡིག', 'Русское название']) {
      expect(
        LibraryQuery(text: term)
            .apply([item(metadata: restored)], TasteProfile()),
        hasLength(1),
      );
    }
    expect(MetadataLanguage.rtl('ar-SA'), isTrue);
    expect(MetadataLanguage.rtl('bo-CN'), isFalse);
  });
  test('regional file and channel names retain Unicode scripts', () {
    for (final title in [
      '日本語題名',
      '한국 영화',
      '香港繁體',
      '台灣片名',
      'Русский фильм',
      'Película española',
      'فيلم عربي',
      'བོད་ཡིག',
    ]) {
      expect(FilenameParser.parse('$title.2024.1080p.mkv').title, title);
      expect(
        M3UParser.parse(
          '#EXTM3U\n#EXTINF:-1,$title\nhttps://example.test/live',
          playlistId: 'p',
        ).single.name,
        title,
      );
    }
  });

  group('regional provider data', () {
    late HttpServer server;
    final requests = <Uri>[];
    var wrongId = false;
    setUp(() async {
      requests.clear();
      wrongId = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        requests.add(req.uri);
        req.response.headers.contentType = ContentType.json;
        final translations = {
          'id': wrongId ? 99 : 42,
          'translations': [
            {
              'iso_639_1': 'zh',
              'iso_3166_1': 'HK',
              'data': {'title': '港名', 'overview': '港版簡介'},
            },
            {
              'iso_639_1': 'zh',
              'iso_3166_1': 'TW',
              'data': {'title': '台名', 'overview': '台版簡介'},
            },
            {
              'iso_639_1': 'ar',
              'iso_3166_1': 'SA',
              'data': {'title': 'عنوان عربي', 'overview': ''},
            },
            {
              'iso_639_1': 'bo',
              'iso_3166_1': 'CN',
              'data': {'title': '', 'overview': ''},
            },
          ],
        };
        if (req.uri.path.endsWith('/translations'))
          req.response.write(jsonEncode(translations));
        else if (req.uri.path.contains('/search/')) {
          if (req.uri.queryParameters['language'] == 'ko-KR')
            req.response.statusCode = 503;
          req.response.write(
            jsonEncode({
              'results': [
                {'id': 42, 'title': 'Original'},
              ],
              'total_pages': 2,
            }),
          );
        } else
          req.response.write(
            jsonEncode({
              'id': 42,
              'title': 'Original',
              'overview': 'Summary',
              'translations': translations,
              'alternative_titles': {
                'titles': [
                  {'iso_3166_1': 'ES', 'title': 'Título español'},
                ],
              },
            }),
          );
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));
    TmdbClient client() => TmdbClient(
      'fixture',
      base: Uri.parse('http://127.0.0.1:${server.port}/3'),
      locale: const MetadataLocale(
        additionalLanguages: MetadataLanguage.defaults,
      ),
    );
    test('one detail preserves real language variants and aliases without inventing Tibetan', () async {
      final c = client();
      addTearDown(c.close);
      final result = await c.details(base);
      expect(result.localized.keys, containsAll(['zh-HK', 'zh-TW', 'ar-SA']));
      expect(result.localized.containsKey('bo-CN'), isFalse);
      expect(result.alternativeTitles['ES'], ['Título español']);
      expect(
        requests.single.queryParameters['append_to_response'],
        contains('translations'),
      );
      expect(
        requests.single.queryParameters['include_image_language'],
        contains('bo'),
      );
    });
    test('multi-region search deduplicates IDs, reports partial failures and restores locale', () async {
      final c = client();
      addTearDown(c.close);
      final original = c.locale;
      final results = await c.searchRegional('原題');
      expect(results, hasLength(1));
      expect(c.regionalErrors, ['ko-KR']);
      expect(c.hasMore, isTrue);
      expect(identical(original, c.locale), isTrue);
      expect(
        requests.map((r) => r.queryParameters['language']),
        containsAll(MetadataLanguage.defaults),
      );
      expect(
        requests
            .where((r) => r.queryParameters['language'] == 'zh-HK')
            .single
            .queryParameters['region'],
        'HK',
      );
    });
    test('real provider fields supersede machine fields; identity mismatch is rejected', () async {
      final c = client();
      addTearDown(c.close);
      final old = base.withLanguages({
        'zh-HK': const LocalizedMetadata(
          title: '机译旧名',
          titleOrigin: 'machine',
          engine: 'fixture',
        ),
      });
      final refreshed = await c.collectTranslations(old);
      expect(refreshed.localized['zh-HK']!.title, '港名');
      expect(refreshed.localized['zh-HK']!.titleOrigin, 'source');
      wrongId = true;
      await expectLater(c.collectTranslations(old), throwsFormatException);
    });
  });

  group('local translation boundary', () {
    late HttpServer server;
    final payloads = <Map<String, dynamic>>[];
    Map<String, dynamic> answer = {};
    Completer<void>? received;
    var stall = false;
    setUp(() async {
      payloads.clear();
      received = null;
      stall = false;
      answer = {'title': 'བོད་ཡིག', 'overview': 'བོད་ཡིག་གི་བརྗོད་བྱ།'};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final j = jsonDecode(
          await utf8.decoder.bind(req).join(),
        ) as Map<String, dynamic>;
        payloads.add(j);
        received?.complete();
        if (stall) return;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(answer)},
              },
            ],
          }),
        );
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));
    LocalMetadataTranslator translator() => LocalMetadataTranslator(
      LocalTranslationConfig(
        endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
        model: 'fixture-local',
      ),
      timeout: const Duration(seconds: 3),
    );
    test('local translation only sends missing fields and retains original provider titles', () async {
      final c = translator();
      addTearDown(c.close);
      final metadata = base.withLanguages({
        'zh-HK': const LocalizedMetadata(title: '已有港名', provider: 'tmdb'),
      });
      answer = {'overview': '補充簡介', 'title': '不应覆盖'};
      final result = await c.translate(
        item(metadata: metadata),
        metadata,
        'zh-HK',
      );
      expect(result.title, '已有港名');
      expect(result.titleOrigin, 'source');
      expect(result.overviewOrigin, 'machine');
      final body = jsonDecode(
        payloads.single['messages'][1]['content'] as String,
      ) as Map;
      expect((body['fields'] as Map).containsKey('title'), isFalse);
      expect(jsonEncode(payloads), isNot(contains('SECRET')));
      expect(jsonEncode(payloads), isNot(contains('/private/video')));
      expect(jsonEncode(payloads), isNot(contains('PRIVATE')));
    });
    test('Tibetan requires Tibetan script, and model-generated extra fields are rejected', () async {
      final c = translator();
      addTearDown(c.close);
      final result = await c.translate(item(), base, 'bo-CN');
      expect(result.titleOrigin, 'machine');
      expect(result.engine, 'fixture-local');
      answer = {'title': 'English', 'overview': 'English summary'};
      await expectLater(
        c.translate(item(), base, 'bo-CN'),
        throwsFormatException,
      );
      answer = {'title': 'Translated', 'overview': 'Text', 'rating': 10};
      await expectLater(
        c.translate(item(), base, 'es-ES'),
        throwsFormatException,
      );
    });
    test('role-only translation retains personnel names and authentic title fields', () async {
      final c = translator();
      addTearDown(c.close);
      final metadata =
          MediaMetadata.fromJson({
            ...base.toJson(),
            'people': [
              const MediaPerson(
                name: '本名',
                role: 'Director',
                department: 'Directing',
              ).toJson(),
            ],
          }).withLanguages({
            'ar-SA': const LocalizedMetadata(
              title: 'عنوان',
              overview: 'ملخص',
              provider: 'tmdb',
            ),
          });
      expect(
        LocalMetadataTranslator.needsTranslation(metadata, 'ar-SA'),
        isTrue,
      );
      answer = {
        'roles': {'0': 'مخرج'},
      };
      final result = await c.translate(item(), metadata, 'ar-SA');
      expect(result.titleOrigin, 'source');
      expect(result.roles['0'], 'مخرج');
      expect(metadata.people.single.name, '本名');
      expect(jsonEncode(payloads), isNot(contains('本名')));
    });
    test('restricted sources, external endpoints and explicit cloud models never run', () async {
      final c = translator();
      addTearDown(c.close);
      await expectLater(
        c.translate(item(aiAllowed: false), base, 'bo-CN'),
        throwsFormatException,
      );
      expect(payloads, isEmpty);
      for (final url in [
        'https://remote.example/v1/chat/completions',
        'http://127.0.0.1.evil.test/v1/chat/completions',
        'http://192.168.1.2/v1/chat/completions',
      ]) {
        expect(
          () =>
              LocalTranslationConfig(endpoint: url, model: 'local').validate(),
          throwsFormatException,
        );
      }
      expect(
        () => const LocalTranslationConfig(model: 'model:cloud').validate(),
        throwsFormatException,
      );
    });
    test(
      'in-flight requests can be cancelled without returning a draft',
      () async {
        final c = translator();
        addTearDown(c.close);
        received = Completer<void>();
        stall = true;
        final pending = c.translate(item(), base, 'bo-CN');
        final expectation = expectLater(
          pending,
          throwsA(isA<TranslationCancelled>()),
        );
        await received!.future;
        c.cancel();
        await expectation;
      },
    );
  });

  group('batch persistence', () {
    late Directory dir;
    late LibraryStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('seewow-regional-');
      store = LibraryStore(directory: dir)
        ..items.addAll([item(metadata: base), item(id: 'b', metadata: base)]);
    });
    tearDown(() async {
      store.dispose();
      await dir.delete(recursive: true);
    });
    MetadataLanguageDraft draft(MediaItem original) => MetadataLanguageDraft(
      itemId: original.id,
      before: metadataSnapshot(original),
      metadata: base.withLanguages({
        'bo-CN': LocalizedMetadata(
          title: 'བོད་ཡིག',
          titleOrigin: 'machine',
          engine: 'fixture',
          inputHash: LocalMetadataTranslator.sourceHash(base),
        ),
      }),
      generatedByModel: true,
    );
    test('concurrent metadata edits reject the whole batch; playback progress does not', () async {
      final drafts = store.items.map(draft).toList();
      store.items[1] = store.items[1].copyWith(title: 'Edited');
      await expectLater(
        store.applyLanguageDrafts(drafts),
        throwsFormatException,
      );
      expect(store.items.first.metadata!.localized, isEmpty);
      final fresh = draft(store.items.first);
      store.items[0] = store.items[0].copyWith(position: 123);
      await store.applyLanguageDrafts([fresh]);
      expect(store.items.first.position, 123);
      expect(store.items.first.title, 'Original');
      final reload = LibraryStore(directory: dir);
      await reload.load();
      expect(
        reload.items.first.metadata!.localized['bo-CN']!.engine,
        'fixture',
      );
      reload.dispose();
    });
    test(
      'unreviewed NFO updates retain translations and mark machine text stale',
      () async {
        final raw = item(
          metadata: MediaMetadata.fromJson({
            ...base.toJson(),
            'id': 0,
            'provider': 'nfo',
            'reviewed': false,
          }),
        );
        store.items
          ..clear()
          ..add(raw);
        final m = raw.metadata!;
        await store.applyLanguageDrafts([
          MetadataLanguageDraft(
            itemId: raw.id,
            before: metadataSnapshot(raw),
            metadata: m.withLanguages({
              'bo-CN': LocalizedMetadata(
                title: 'བོད་ཡིག',
                titleOrigin: 'machine',
                inputHash: LocalMetadataTranslator.sourceHash(m),
              ),
            }),
            generatedByModel: true,
          ),
        ]);
        final source = MediaSource(
          id: 'nas',
          kind: SourceKind.local,
          name: 'NAS',
          location: '/media',
        );
        store.sources.add(source);
        store.scanner = (_) async => [
          raw.copyWith(
            title: 'New source title',
            metadata: MediaMetadata.fromJson({
              ...m.toJson(),
              'title': 'New source title',
            }),
          ),
        ];
        await store.rescan(source);
        expect(store.items.single.title, 'New source title');
        expect(store.items.single.metadata!.reviewed, isFalse);
        expect(
          LocalMetadataTranslator.needsTranslation(
            store.items.single.metadata!,
            'bo-CN',
          ),
          isTrue,
        );
      },
    );
  });
}
