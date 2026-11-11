import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/features/metadata_dialog.dart';
import 'package:seewow/features/metadata_editor.dart';
import 'package:seewow/features/subtitle_dialog.dart';
import 'package:seewow/metadata/subtitles.dart';
import 'package:seewow/metadata/tmdb_client.dart';

class _Tmdb extends TmdbClient {
  _Tmdb() : super('fixture');
  String? requestedLanguage;
  @override
  Future<List<MediaMetadata>> search(
    String query, {
    bool series = false,
    int? year,
    int page = 1,
  }) async {
    requestedLanguage = locale.language;
    return [
      const MediaMetadata(
        id: 1,
        mediaType: 'movie',
        title: '日本語題名',
        originalTitle: 'Original',
        people: [MediaPerson(name: '監督', role: 'Director')],
        ratings: [MediaRating(source: 'TMDB', value: 8.2)],
        artworks: [
          MediaArtwork(url: 'https://image.test/ja.jpg', language: 'ja'),
        ],
      ),
    ];
  }

  @override
  Future<MediaMetadata> details(MediaMetadata candidate) async => candidate;
}

class _Subtitles extends OpenSubtitlesClient {
  _Subtitles() : super('fixture');
  int searches = 0, downloads = 0;
  @override
  Future<List<SubtitleCandidate>> search(
    MediaItem item, {
    String? query,
    String languages = '',
    int page = 1,
  }) async {
    searches++;
    return [
      const SubtitleCandidate(
        fileId: 1,
        filename: 'Movie.ar.srt',
        language: 'ar',
        release: 'WEB-DL',
      ),
    ];
  }

  @override
  Future<String> download(SubtitleCandidate candidate) async {
    downloads++;
    return '1\n00:00:00,000 --> 00:00:01,000\nمرحبا';
  }
}

void main() {
  late Directory dir;
  late LibraryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-scrape-flow-');
    store = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'a',
          sourceId: 'local',
          kind: MediaKind.audio,
          title: 'Original',
          locator: '/track.flac',
          position: 42,
        ),
      );
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    double width,
    Widget Function(BuildContext) button,
  ) async {
    tester.view.physicalSize = Size(width, 800);
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
        home: Scaffold(body: Builder(builder: button)),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets(
      'metadata editor and subtitle selection remain usable at $width',
      (tester) async {
        await mount(
          tester,
          width,
          (context) => TextButton(
            onPressed: () => editMetadata(context, store, store.items.single),
            child: const Text('Open'),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '标题',
          ),
          '音楽 مرحبا',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('保存媒体资料'));
          await store.save();
        });
        await tester.pumpAndSettle();
        expect(store.items.single.title, '音楽 مرحبا');
        expect(store.items.single.position, 42);
        final subs = _Subtitles();
        DownloadedSubtitle? picked;
        await mount(
          tester,
          width,
          (context) => TextButton(
            onPressed: () async {
              picked = await findSubtitle(
                context,
                store.items.single,
                clientFactory: () async => subs,
              );
            },
            child: const Text('Open'),
          ),
        );
        expect(subs.searches, 0);
        await tester.ensureVisible(find.text('查找字幕'));
        await tester.tap(find.text('查找字幕'));
        await tester.pumpAndSettle();
        expect(subs.searches, 1);
        expect(subs.downloads, 0);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Movie.ar.srt'));
        await tester.tap(find.text('Movie.ar.srt'));
        await tester.pumpAndSettle();
        expect(subs.downloads, 1);
        expect(picked?.language, 'ar');
        expect(picked?.text, contains('مرحبا'));
      },
    );
  }
  testWidgets(
    'locale controls reach the scraper and cancelling reviewed details leaves data unchanged',
    (tester) async {
      final tmdb = _Tmdb();
      final item = MediaItem(
        id: 'movie',
        sourceId: 's',
        kind: MediaKind.movie,
        title: 'Film',
        locator: '/film.mkv',
      );
      store.items.add(item);
      await mount(
        tester,
        375,
        (context) => TextButton(
          onPressed: () => matchMetadata(
            context,
            store,
            item,
            clientFactory: () async => tmdb,
          ),
          child: const Text('Open'),
        ),
      );
      final language = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '资料语言',
      );
      await tester.ensureVisible(language);
      await tester.enterText(language, 'ja-JP');
      await tester.ensureVisible(find.byTooltip('搜索 TMDB'));
      await tester.tap(find.byTooltip('搜索 TMDB'));
      await tester.pumpAndSettle();
      expect(tmdb.requestedLanguage, 'ja-JP');
      await tester.ensureVisible(find.text('日本語題名'));
      await tester.tap(find.text('日本語題名'));
      await tester.pumpAndSettle();
      expect(find.text('原名：Original'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.items.last.metadata, isNull);
    },
  );
}
