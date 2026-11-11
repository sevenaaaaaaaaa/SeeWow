import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/domain/metadata_languages.dart';
import 'package:seewow/features/metadata_language_batch.dart';
import 'package:seewow/features/metadata_languages_view.dart';
import 'package:seewow/metadata/tmdb_client.dart';
import 'package:seewow/metadata/local_metadata_translation.dart';

class _Source extends TmdbClient {
  _Source() : super('fixture');
  @override
  Future<MediaMetadata> collectTranslations(
    MediaMetadata metadata, {
    int? seriesId,
    int? season,
    int? episode,
  }) async => metadata.withLanguages(
    {
      'zh-HK': const LocalizedMetadata(
        title: '港版名稱',
        overview: '港版資料',
        provider: 'tmdb',
      ),
      'zh-TW': const LocalizedMetadata(
        title: '台灣片名',
        overview: '台灣資料',
        provider: 'tmdb',
      ),
    },
    preferred: ['zh-HK', 'zh-TW'],
  );
}

class _Translator extends LocalMetadataTranslator {
  _Translator(super.config);
  int calls = 0;
  @override
  Future<LocalizedMetadata> translate(
    MediaItem item,
    MediaMetadata metadata,
    String target,
  ) async {
    calls++;
    return LocalizedMetadata(
      title: 'བོད་ཡིག',
      overview: 'བོད་ཡིག་གི་བརྗོད་བྱ།',
      titleOrigin: 'machine',
      overviewOrigin: 'machine',
      engine: 'fixture-local',
      inputHash: LocalMetadataTranslator.sourceHash(metadata),
    );
  }
}

void main() {
  setUpAll(() async {
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    for (final family in ['NotoSerifTibetan', 'NotoSansArabic']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family-Variable.ttf'))).load();
    }
    final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (file.existsSync())
      await (FontLoader('CinemaTest')..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          ))
          .load();
  });
  late Directory dir;
  late LibraryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-regional-flow-');
    store = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'm',
          sourceId: 'nas',
          kind: MediaKind.movie,
          title: 'Original',
          locator: '/video.mkv',
          position: 42,
          metadata: const MediaMetadata(
            id: 42,
            mediaType: 'movie',
            title: 'Original',
            overview: 'Original synopsis',
          ),
        ),
      );
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester,
    double width, {
    LocalMetadataTranslator Function(LocalTranslationConfig)? translator,
  }) async {
    tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(width == 375 ? 1.6 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => manageMetadataLanguages(
                context,
                store,
                store.items,
                tmdbFactory: () async => _Source(),
                translatorFactory: translator,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets(
      'regional batch collection fits $width and cancel never commits',
      (tester) async {
        await open(tester, width);
        await tester.ensureVisible(find.text('采集现有文字译文'));
        await tester.tap(find.text('采集现有文字译文'));
        await tester.pumpAndSettle();
        expect(store.items.single.metadata!.localized, isEmpty);
        expect(find.text('保存所选预览（1）'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(store.items.single.metadata!.localized, isEmpty);
      },
    );
  }
  testWidgets(
    'batch translation previews Tibetan and preserves original title and playback until confirmation',
    (tester) async {
      late _Translator translator;
      await open(
        tester,
        768,
        translator: (config) => translator = _Translator(config),
      );
      for (final profile in MetadataLanguage.regional.where(
        (p) => p.tag != 'bo-CN',
      )) {
        await tester.tap(find.widgetWithText(FilterChip, profile.name));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('本机翻译模型设置'));
      await tester.tap(find.text('本机翻译模型设置'));
      await tester.pumpAndSettle();
      final model = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '已安装的本地模型名称',
      );
      await tester.ensureVisible(model);
      await tester.enterText(model, 'fixture-local');
      await tester.ensureVisible(find.text('本机补译缺失／过期文字'));
      await tester.tap(find.text('本机补译缺失／过期文字'));
      await tester.pumpAndSettle();
      expect(translator.calls, 1);
      expect(store.items.single.metadata!.localized, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.text('保存所选预览（1）'));
        await store.save();
      });
      await tester.pumpAndSettle();
      expect(
        store.items.single.metadata!.localized['bo-CN']!.engine,
        'fixture-local',
      );
      expect(store.items.single.title, 'Original');
      expect(store.items.single.position, 42);
    },
  );
  testWidgets(
    'Arabic is RTL and Tibetan selects the bundled font in simultaneous cards',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final metadata = const MediaMetadata(
        id: 42,
        mediaType: 'movie',
        title: 'Original',
        preferredLanguages: ['ar-SA', 'bo-CN'],
        localized: {
          'ar-SA': LocalizedMetadata(
            title: 'رحلة إلى المنزل',
            overview: 'تعود عائلة إلى منزلها وتلتقي بأصدقاء قدامى.',
            provider: 'tmdb',
          ),
          'bo-CN': LocalizedMetadata(
            title: 'བོད་ཡིག',
            overview: 'བོད་ཡིག་གི་བརྗོད་བྱ།',
            titleOrigin: 'machine',
            overviewOrigin: 'machine',
            engine: '本机模型',
          ),
        },
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('regional-shot'),
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: Platform.environment['SEEWOW_SHOTS'] == '1'
                    ? 'CinemaTest'
                    : null,
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: MetadataLanguagesView(metadata: metadata),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final arabic = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'رحلة إلى المنزل',
        ),
      );
      final tibetan = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'བོད་ཡིག',
        ),
      );
      expect(arabic.textDirection, TextDirection.rtl);
      expect(arabic.textAlign, TextAlign.right);
      final arabicTitle = find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'رحلة إلى المنزل',
      );
      expect(tester.getSize(arabicTitle).width, greaterThan(350));
      expect(tibetan.style!.fontFamily, 'NotoSerifTibetan');
      expect(tester.takeException(), isNull);
      if (Platform.environment['SEEWOW_SHOTS'] == '1')
        await tester.runAsync(() async {
          final shot = await tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('regional-shot')),
              )
              .toImage();
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/seewow-regional-languages.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          shot.dispose();
        });
    },
  );
}
