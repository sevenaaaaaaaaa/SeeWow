import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/cinema_widgets.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/features/cover_generation_view.dart';
import 'package:seewow/features/custom_scraper_view.dart';
import 'package:seewow/metadata/cover_generator.dart';
import 'package:seewow/metadata/custom_scraper.dart';

class _Repository extends CustomScraperRepository {
  final profile = CustomScraperProfile(
    id: 'fixture',
    name: '课程 API',
    category: '课程',
    baseUrl: 'https://fixture.test',
  );
  final clientInstance = _Client();
  @override
  Future<List<CustomScraperProfile>> load() async => [profile];
  @override
  Future<CustomScraperClient> client(CustomScraperProfile profile) async =>
      clientInstance;
}

class _Client extends CustomScraperClient {
  _Client()
    : super(
        CustomScraperProfile(
          id: 'fixture',
          name: '课程 API',
          baseUrl: 'https://fixture.test',
        ),
      );
  int searches = 0;
  @override
  Future<List<MediaMetadata>> search(
    MediaItem item,
    String query, {
    String language = 'zh-CN',
  }) async {
    searches++;
    return [
      const MediaMetadata(
        id: 0,
        provider: 'custom:fixture',
        mediaType: 'other',
        title: '课程资料标题',
        overview: '课程简介',
        people: [MediaPerson(name: '讲师', role: 'Teacher')],
        ratings: [MediaRating(source: 'Campus', value: 4.5, scale: 5)],
      ),
    ];
  }

  @override
  Future<MediaMetadata> details(
    MediaMetadata candidate,
    MediaItem item,
  ) async => candidate;
}

class _Generator extends CoverGenerator {
  _Generator(this.bytes, {this.fail = false})
    : super(const CoverGenerationConfig());
  final Uint8List bytes;
  final bool fail;
  int calls = 0;
  String? prompt;
  @override
  Future<GeneratedCover> generate(MediaItem item, String prompt) async {
    calls++;
    this.prompt = prompt;
    if (fail) throw const FormatException('Fixture generation failed');
    return GeneratedCover(
      bytes: bytes,
      model: 'fixture-art',
      createdAt: DateTime.utc(2026),
    );
  }
}

void main() {
  late Directory dir;
  late LibraryStore store;
  late Uint8List png;
  setUpAll(() async {
    if (Platform.environment['SEEWOW_SHOTS'] == '1') {
      final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
      if (await font.exists()) {
        await (FontLoader('CinemaTest')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 60),
      ui.Paint()..color = const Color(0xff30556d),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 60);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-custom-flow-');
    store = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'a',
          sourceId: 'nas',
          kind: MediaKind.other,
          title: 'Original course',
          locator: '/private/video.mp4',
          position: 42,
        ),
      );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('seewow/native'),
          (call) async => call.method == 'secret.write' ? true : null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('seewow/native'), null);
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    double width,
    Widget Function(BuildContext) open, {
    double height = 850,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('custom-shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: width == 768 ? Brightness.light : Brightness.dark,
            fontFamily: Platform.environment['SEEWOW_SHOTS'] == '1'
                ? 'CinemaTest'
                : null,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 375 ? 1.6 : 1)),
            child: child!,
          ),
          home: Scaffold(body: Builder(builder: open)),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.runAsync(() async {
      await tester.tap(find.text(label).last);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();
  }

  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 160)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    await tester.runAsync(() async {
      final shot = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('custom-shot')),
          )
          .toImage();
      final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/seewow-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      shot.dispose();
    });
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets('custom API and image settings remain reachable at $width', (
      tester,
    ) async {
      await mount(
        tester,
        width,
        (context) => TextButton(
          onPressed: () =>
              configureCustomScrapers(context, repository: _Repository()),
          child: const Text('Open'),
        ),
      );
      expect(find.text('自定义刮削 API'), findsOneWidget);
      if (width == 768) await screenshot(tester, 'custom-api-settings');
      await tap(tester, '保存适配');
      await settleIo(tester);
      if (find.text('取消').evaluate().isNotEmpty) await tap(tester, '取消');
      await mount(
        tester,
        width,
        (context) => TextButton(
          onPressed: () => configureCoverGeneration(context),
          child: const Text('Open'),
        ),
      );
      await tap(tester, '保存封面服务');
      expect(find.textContaining('服务地址需为'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, '取消');
      expect(store.items.single.metadata, isNull);
    });
  }
  testWidgets(
    'custom metadata preview is invalidated by query changes and requires confirmation',
    (tester) async {
      final repository = _Repository();
      await mount(
        tester,
        768,
        (context) => TextButton(
          onPressed: () => matchCustomMetadata(
            context,
            store,
            store.items.single,
            repository: repository,
          ),
          child: const Text('Open'),
        ),
      );
      await tap(tester, '搜索资料');
      await tap(tester, '课程资料标题');
      expect(find.text('预览：课程资料标题'), findsOneWidget);
      expect(store.items.single.title, 'Original course');
      await tester.enterText(find.byType(TextField).first, 'Different query');
      await tester.pumpAndSettle();
      expect(find.text('预览：课程资料标题'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认当前条目'))
            .onPressed,
        isNull,
      );
      await tap(tester, '搜索资料');
      await tap(tester, '课程资料标题');
      await tap(tester, '确认当前条目');
      await settleIo(tester);
      expect(store.items.single.title, '课程资料标题');
      expect(store.items.single.position, 42);
      expect(store.items.single.locator, '/private/video.mp4');
      expect(repository.clientInstance.searches, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel after cover generation leaves no cover file or metadata',
    (tester) async {
      final generator = _Generator(png);
      await mount(
        tester,
        375,
        (context) => TextButton(
          onPressed: () => generateMediaCover(
            context,
            store,
            store.items.single,
            generatorFactory: () async => generator,
          ),
          child: const Text('Open'),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'My original illustration',
      );
      await tap(tester, '生成封面预览');
      expect(find.textContaining('AI 配图 · fixture-art'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('AI 配图 · fixture-art'));
      for (var frame = 0; frame < 3; frame++) {
        await settleIo(tester);
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await screenshot(tester, 'cover-preview-375');
      expect(store.items.single.posterUrl, isNull);
      await tap(tester, '取消');
      expect(
        await tester.runAsync(() => Directory('${dir.path}/covers').exists()),
        isFalse,
      );
      expect(store.items.single.metadata, isNull);
      expect(generator.prompt, 'My original illustration');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'confirm cover writes a local image, keeps progress and displays AI provenance',
    (tester) async {
      final generator = _Generator(png);
      await mount(
        tester,
        768,
        (context) => TextButton(
          onPressed: () => generateMediaCover(
            context,
            store,
            store.items.single,
            generatorFactory: () async => generator,
          ),
          child: const Text('Open'),
        ),
      );
      await tap(tester, '生成封面预览');
      await tap(tester, '保存封面');
      await settleIo(tester);
      expect(store.items.single.hasGeneratedCover, isTrue);
      expect(store.items.single.position, 42);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: FilmArtwork(item: store.items.single),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(find.text('AI 配图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: SizedBox(
                width: 38,
                height: 52,
                child: FilmArtwork(item: store.items.single),
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(find.text('AI'), findsOneWidget);
      final art = tester.getRect(find.byType(FilmArtwork));
      final badge = tester.getRect(find.text('AI'));
      expect(art.contains(badge.topLeft), isTrue);
      expect(art.contains(badge.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('generation errors and restricted sources never save a cover', (
    tester,
  ) async {
    final generator = _Generator(png, fail: true);
    await mount(
      tester,
      900,
      (context) => TextButton(
        onPressed: () => generateMediaCover(
          context,
          store,
          store.items.single,
          generatorFactory: () async => generator,
        ),
        child: const Text('Open'),
      ),
      height: 450,
    );
    await tap(tester, '生成封面预览');
    expect(find.text('Fixture generation failed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存封面'))
          .onPressed,
      isNull,
    );
    await tap(tester, '取消');
    store.items[0] = MediaItem(
      id: 'a',
      sourceId: 'telegram',
      kind: MediaKind.other,
      title: 'Restricted',
      locator: '/a',
      aiAllowed: false,
    );
    await mount(
      tester,
      900,
      (context) => TextButton(
        onPressed: () => generateMediaCover(
          context,
          store,
          store.items.single,
          generatorFactory: () async => generator,
        ),
        child: const Text('Open'),
      ),
      height: 450,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '生成封面预览'))
          .onPressed,
      isNull,
    );
    expect(generator.calls, 1);
    expect(store.items.single.posterUrl, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final stop in [true, false]) {
    testWidgets(
      'late image service setup respects ${stop ? 'stop' : 'changed AI restrictions'} before transmitting',
      (tester) async {
        final pending = Completer<CoverGenerator>();
        final generator = _Generator(png);
        await mount(
          tester,
          768,
          (context) => TextButton(
            onPressed: () => generateMediaCover(
              context,
              store,
              store.items.single,
              generatorFactory: () => pending.future,
            ),
            child: const Text('Open'),
          ),
        );
        await tester.ensureVisible(find.text('生成封面预览'));
        await tester.tap(find.text('生成封面预览'));
        await tester.pump();
        if (stop) {
          await tester.ensureVisible(find.text('停止生成'));
          await tester.tap(find.text('停止生成'));
        } else {
          store.items[0] = MediaItem.fromJson({
            ...store.items.single.toJson(),
            'aiAllowed': false,
          });
        }
        pending.complete(generator);
        await tester.pumpAndSettle();
        expect(generator.calls, 0);
        expect(store.items.single.posterUrl, isNull);
        expect(
          find.textContaining(stop ? '已停止生成' : '媒体资料或来源已改变'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
